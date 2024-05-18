#!/usr/bin/env python3

import os
import json
import sys


ast_json = None
with open('build/slurped-ast.json') as f:
    ast_json = json.load(f)

main_node_json = None
for node in ast_json:
    if "mangledName" in node and node["mangledName"] == "_main":
        main_node_json = node
        

# collect nodes ahead of time
def collect_nodes_by_id(node, ids_to_nodes):
    if "inner" in node:
        for inner_node in node["inner"]:
            collect_nodes_by_id(inner_node, ids_to_nodes)
    ids_to_nodes[node["id"]] = node


class Node():
    def __init__(self, node_json):
        self.kind = node_json.get("kind")
        self.id = node_json.get("id")
        self.inner_json = node_json.get("inner")
        self.loc = node_json.get("loc")
        self.mangledName = node_json.get("mangledName")
        self.type = node_json.get("type")
        if self.type:
            self.type = self.type.get("qualType")
        self.receiverKind = node_json.get("receiverKind")
        self.value = node_json.get("value")
        self.name = node_json.get("name")
        self.classType = node_json.get("classType")
        if self.classType:
            self.classType = self.classType.get("qualType")
        self.selector = node_json.get("selector")
        self.inner_nodes = []

    def str_with_depth(self, depth = 0):
       sys.exit('Invalid call to Superclass "Node"')
    
    def __str__(self):
       self.str_with_depth(depth=0)


class StringLiteralNode(Node):
    def str_with_depth(self, depth = 0):
       s = "\t" * depth + " " + self.kind + ": "
       s += " " +  self.value
       return s
    
    def expr(self):
        # TODO likely have to do encoding here for quote issues
        return self.value
   

class IntegerLiteralNode(Node):
    def str_with_depth(self, depth = 0):
       s = "\t" * depth + " " + self.kind + ": "
       s += self.value
       return  s      

    def expr(self):     
        """
        NSString selectors
        intValue
        The integer value of the string.
        integerValue
        The NSInteger value of the string.
        longLongValue
        """
        ns_string_selector = ""
        t = self.type
        match t:
            case "unsigned long":
                ns_string_selector = 'integerValue'
            case "unsigned long long":
                ns_string_selector = 'longLongValue'
            case _:
                # this is expected to be "int" or "bool", warn if that's not correct
                if self.type not in  ["int", "bool"]:
                    print(f"[WARNING] Unexpected type for {self.__name__}: {t}")
                ns_string_selector = 'intValue'
        
        expr = f"FUNCTION('{self.value}','{ns_string_selector}')"
        return expr


class FloatingLiteralNode(Node):
    def str_with_depth(self, depth = 0):
       s = "\t" * depth + " " + self.kind + ": "
       s += self.value
       return  s      

    def expr(self):     
        ns_string_selector = ""
        t = self.type
        match t:
            case "float":
                ns_string_selector = 'floatValue'
            case _:
                # this is expected to be "int" or "bool", warn if that's not correct
                if self.type not in  ["int", "bool"]:
                    print(f"[WARNING] Unexpected type for {self.__name__}: {t}")
                ns_string_selector = 'intValue'
        
        expr = f"FUNCTION('{self.value}','{ns_string_selector}')"
        return expr


class ObjCStringLiteralNode(Node):
    def str_with_depth(self, depth = 0):
        t = self.type
        v = self.inner_nodes[0].value
        s = "\t" * depth + " " + self.kind + ": "
        s += t + " " + v
        return s
    
    def expr(self):
        # reach down to the first inner node, expected to be
        # StringLiteral, and return it's value
        return self.inner_nodes[0].expr()


class ObjCMessageExprNode(Node):
    def str_with_depth(self, depth = 0):
        class_and_selector = ""
        if  self.receiverKind == "class":
            class_and_selector += self.classType + " "
        class_and_selector += self.selector
        s = "\t" * depth + " " + self.kind + ":"
        s += " " + class_and_selector
        return s

    def expr(self):
        # two types, either the first argument is a class (which we need to generate)
        # or an instance (from a chained call)
        expr = "FUNCTION("
        copy_of_inner_nodes = self.inner_nodes.copy()
        if self.receiverKind == "class":
            expr +=  f"CAST('{self.classType}','Class'),'{self.selector}'"
        else:
            # remove first inner node to leave only selectors
            temp_expr = copy_of_inner_nodes.pop(0).expr()
            expr +=  f"{temp_expr},'{self.selector}'"

        # fill selectors
        
        selector_array = self.selector.split(":")
        for inner in copy_of_inner_nodes:
            expr += f",{inner.expr()}"
        expr += ")"
        return expr
      
   
class ImplicitCastExprNode(Node):
    def str_with_depth(self, depth = 0):
       s = "\t" * depth + " " + self.kind + ":"
       return s
   
    def expr(self):
        # reach down and bubble up the first (and expected to be only) inner node expr
        return self.inner_nodes[0].expr()


class FunctionDeclNode(Node):
    def str_with_depth(self, depth = 0):
       s = "\t" * depth + " " + self.kind + ":"
       return s
    
    def expr(self):
        # reach down to the first inner node, expected to be
        # ObjCMessageExprNode, and return it's value.
        return self.inner_nodes[0].expr()
        

class CompoundStmtNode(Node):
    def str_with_depth(self, depth = 0):
       s = "\t" * depth + " " + self.kind + ":"
       return s
   
    def expr(self):
        # for each inner node (aka line of code), print independent function expressions
        copy_of_inner_nodes = self.inner_nodes.copy()
        expr = f"FUNCTION(CAST('NSNull','Class'),'alloc',{copy_of_inner_nodes.pop(0).expr()})"
        for inner in copy_of_inner_nodes:
            expr = f"FUNCTION(CAST('NSNull','Class'),'alloc', {expr}, {inner.expr()})"
        return expr


def parse_nodes_recursively(node_json):
    kind = node_json["kind"]
    node = None
    match kind:
        case "StringLiteral":
            node = StringLiteralNode(node_json)
        case "IntegerLiteral":
            node = IntegerLiteralNode(node_json)
        case "FloatingLiteral":
            node = FloatingLiteralNode(node_json)    
        case "ObjCStringLiteral":
            node = ObjCStringLiteralNode(node_json)
        case "ObjCMessageExpr":
            node = ObjCMessageExprNode(node_json)
        case "ImplicitCastExpr":
            node = ImplicitCastExprNode(node_json)
        case "FunctionDecl":
            node = FunctionDeclNode(node_json)
        case "CompoundStmt":    
            node = CompoundStmtNode(node_json)
        case _:
            print("Unrecognized node kind during recursive parsing:", kind)
    if node.inner_json:
        for inner_node_json in node.inner_json:
            node.inner_nodes.append(parse_nodes_recursively(inner_node_json))
    return node


# Need to use tail recursion to format printing correctly
# meaning not all nodes are available to look up values.
# Collect the nodes ahead of time and pass them in as a dictionary
def visualize_nodes_recursively(node, ids_to_nodes, depth = 0):
    node_kind = node["kind"]
    print("\t" * depth, node_kind + ":")
    match node_kind:
        case "StringLiteral":
            print("\t" * (depth+1), node["value"])
        case "IntegerLiteral":
            print("\t" * (depth+1), node["value"])
        case "ObjCStringLiteral":
            t = node["type"]["qualType"]
            v = ids_to_nodes[node["inner"][0]["id"]]["value"]
            print("\t" * (depth+1), t, v)
        case "ObjCMessageExpr":
            class_and_selector = ""
            if  node["receiverKind"] == "class":
                    class_and_selector += node["classType"]["qualType"] + " "
            class_and_selector += node["selector"]
            print("\t" * (depth+1), class_and_selector)
        case "ImplicitCastExpr":
            pass
        case "FunctionDecl":
            pass
        case "CompoundStmt":    
            pass
        case _:
            print("\t" * (depth+1), "unrecognized node kind:", node_kind)
    print()
    if "inner" in node:
        for inner_node in node["inner"]:
            visualize_nodes_recursively(inner_node, ids_to_nodes, depth+1)


def print_nodes_recursively(node, depth = 0):
    print(node.str_with_depth(depth=depth))
    for inner_node in node.inner_nodes:
        print_nodes_recursively(inner_node, depth+1)


def create_nsexpr_recursively(node):
    expr = ""
    print(node.kind, node.expr())
    for inner_node in node.inner_nodes:
        create_nsexpr_recursively(inner_node)


        
try:
    main_node = parse_nodes_recursively(main_node_json)
    # print the constructed expression(s)
    print(main_node.expr())

# uncomment print all node expressions in a parsable node structure
##############
# print_nodes_recursively(main_node)
# create_nsexpr_recursively(main_node)
##############
except:
# uncomment below to visualize the json that can't be parsed
##############
    ids_to_nodes = {}
    collect_nodes_by_id(main_node_json, ids_to_nodes)
    print(f"collected {len(ids_to_nodes)} nodes ahead of time")
    visualize_nodes_recursively(main_node_json, ids_to_nodes)
##############
