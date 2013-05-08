{-
    BNF Converter: C++ abstract syntax generator
    Copyright (C) 2004  Author:  Michael Pellauer

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{- 
   **************************************************************
    BNF Converter Module

    Description   : This module generates the C++ Abstract Syntax
                    tree classes. It generates both a Header file
                    and an Implementation file, and uses the Visitor
                    design pattern. It uses STL (Standard Template Library).

    Author        : Michael Pellauer (pellauer@cs.chalmers.se)

    License       : GPL (GNU General Public License)

    Created       : 4 August, 2003                           

    Modified      : 22 May, 2004 / Antti-Juhani Kaijanaho
	            29 August, 2006 / Aarne Ranta
   
   ************************************************************** 
-}

module BNFC.Backend.CPP.STL.CFtoSTLAbs (cf2CPPAbs) where

import BNFC.Backend.Common.OOAbstract
import BNFC.CF
import BNFC.Utils((+++),(++++))
import BNFC.Backend.Common.NamedVariables
import Data.List
import Data.Char(toLower)
import BNFC.Backend.CPP.STL.STLUtils

--The result is two files (.H file, .C file)

cf2CPPAbs :: Bool -> Maybe String -> String -> CF -> (String, String)
cf2CPPAbs ln inPackage name cf = (mkHFile ln inPackage cab, mkCFile inPackage cab)
  where
    cab = cf2cabs cf


-- **** Header (.H) File Functions **** --

--Makes the Header file.
mkHFile :: Bool -> Maybe String -> CAbs -> String
mkHFile ln inPackage cf = unlines
 [
  "#ifndef " ++ hdef,
  "#define " ++ hdef,
  "",
  "#include<string>",
  "#include<vector>",
  "",
  "//C++ Abstract Syntax Interface generated by the BNF Converter.",
  nsStart inPackage,
  "/********************   TypeDef Section    ********************/",
  "",
  unlines ["typedef " ++ d ++ " " ++ c ++ ";" | (c,d) <- basetypes],
  "",
  unlines ["typedef std::string " ++ s ++ ";" | s <- tokentypes cf], 
  "",
  "/********************   Forward Declarations    ********************/",
  "",
  unlines ["class " ++ c ++ ";" | c <- classes, notElem c (defineds cf)],
  "",
  "/********************   Visitor Interfaces    ********************/",
  prVisitor cf,
  "",
  prVisitable,
  "",
  "/********************   Abstract Syntax Classes    ********************/",
  "",
  unlines [prAbs ln c | c <- absclasses cf],
  "",
  unlines [prCon (c,r) | (c,rs) <- signatures cf, r <- rs],
  "",
  unlines [prList c | c <- listtypes cf],
  nsEnd inPackage,
  "#endif"
 ]
 where
  classes = allClasses cf
  hdef = nsDefine inPackage "ABSYN_HEADER"

-- auxiliaries

prVisitable :: String
prVisitable = unlines [
  "class Visitable",
  "{",
  " public:",
  -- all classes with virtual methods require a virtual destructor
  "  virtual ~Visitable() {}",
  "  virtual void accept(Visitor *v) = 0;",
  "};"
  ]

prVisitor :: CAbs -> String
prVisitor cf = unlines [
  "class Visitor",
  "{",
  "public:",
  "  virtual ~Visitor() {}",
  unlines 
    ["  virtual void visit"++c++"("++c++" *p) = 0;" | c <- allClasses cf, 
                                                      notElem c (defineds cf)],
  "",
  unlines 
    ["  virtual void visit"++c++"(" ++c++" x) = 0;" | c <- allNonClasses cf],
  "};"
 ]

prAbs :: Bool -> Cat -> String
prAbs ln c = unlines [
  "class " ++c++ " : public Visitable",
  "{",
  "public:",
  "  virtual " ++ c ++ " *clone() const = 0;",
  if ln then "  int line_number;" else "",
  "};"
  ]

prCon :: (Cat,CAbsRule) -> String
prCon (c,(f,cs)) = unlines [
  "class " ++f++ " : public " ++ c,
  "{",
  "public:",
  unlines 
    ["  "++ typ +++ pointerIf st var ++ ";" | (typ,st,var) <- cs],
  "  " ++ f ++ "(const " ++ f ++ " &);",
  "  " ++ f ++ " &operator=(const " ++f++ " &);",
  "  " ++ f ++ "(" ++ conargs ++ ");",
    -- Typ *p1, PIdent *p2, ListStm *p3);
  "  ~" ++f ++ "();",
  "  virtual void accept(Visitor *v);",
  "  virtual " ++f++ " *clone() const;",
  "  void swap(" ++f++ " &);",
  "};"
  ]
 where
   conargs = concat $ intersperse ", " 
     [x +++ pointerIf st ("p" ++ show i) | ((x,st,_),i) <- zip cs [1..]]

prList :: (Cat,Bool) -> String
prList (c,b) = unlines [
  "class " ++c++ " : public Visitable, public std::vector<" ++bas++ ">",
  "{",
  "public:",
  "  virtual void accept(Visitor *v);",
  "  virtual " ++ c ++ " *clone() const;",
  "};"
  ]
 where 
   bas = drop 4 c ++ -- drop List
	 if b then "*" else ""


-- **** Implementation (.C) File Functions **** --

mkCFile :: Maybe String -> CAbs -> String
mkCFile inPackage cf = unlines $ [
  "//C++ Abstract Syntax Implementation generated by the BNF Converter.",
  "#include <algorithm>",
  "#include <string>",
  "#include <iostream>",
  "#include <vector>",
  "#include \"Absyn.H\"",
  nsStart inPackage,
  unlines [prConC  r | (_,rs) <- signatures cf, r <- rs],
  unlines [prListC c | (c,_) <- listtypes cf],
  nsEnd inPackage
  ]

prConC :: CAbsRule -> String
prConC fcs@(f,cs) = unlines [
  "/********************   " ++ f ++ "    ********************/",
  prConstructorC fcs,
  prCopyC fcs,
  prDestructorC fcs,
  prAcceptC f,
  prCloneC f,
  ""
 ]

prListC :: Cat -> String
prListC c = unlines [
  "/********************   " ++ c ++ "    ********************/",
  "",
  prAcceptC c,
  "",
  prCloneC c
 ]


--The standard accept function for the Visitor pattern
prAcceptC :: Cat -> String
prAcceptC ty = unlines [
  "void " ++ ty ++ "::accept(Visitor *v)",
  "{", 
  "  v->visit" ++ ty ++ "(this);",
  "}"
  ]

--The cloner makes a new deep copy of the object
prCloneC :: Cat -> String
prCloneC c = unlines [
  c +++ "*" ++ c ++ "::clone() const", 
  "{",
  "  return new" +++ c ++ "(*this);",
  "}"
  ]

--The constructor assigns the parameters to the corresponding instance variables.
prConstructorC :: CAbsRule -> String
prConstructorC (f,cs) = unlines [
  f ++ "::" ++ f ++ "(" ++ conargs ++ ")",
  "{",
  unlines ["  " ++ c ++ " = " ++ p ++ ";" | (c,p) <- zip cvs pvs],
  "}"
  ]
 where
   cvs = [c | (_,_,c) <- cs]
   pvs = ["p" ++ show i | ((x,st,_),i) <- zip cs [1..]]
   conargs = concat $ intersperse ", " 
     [x +++ pointerIf st v | ((x,st,_),v) <- zip cs pvs]


--Copy constructor and copy assignment
prCopyC :: CAbsRule -> String
prCopyC (c,cs) = unlines [
  c ++ "::" ++ c ++ "(const" +++ c +++ "& other)",
  "{",
  unlines ["  " ++ cv ++ " = other." ++ cloneIf st cv ++ ";" | (_,st,cv) <- cs],
  "}",
  "",
  c +++ "&" ++ c ++ "::" ++ "operator=(const" +++ c +++ "& other)", 
  "{",
  "  " ++ c +++ "tmp(other);",
  "  swap(tmp);",
  "  return *this;",
  "}",
  "",
  "void" +++ c ++ "::swap(" ++ c +++ "& other)", 
  "{",
  unlines ["  std::swap(" ++ cv ++ ", other." ++ cv ++ ");" | (_,_,cv) <- cs],
  "}"
  ]
 where
   cloneIf st cv = if st then (cv ++ "->clone()") else cv

--The destructor deletes all a class's members.
prDestructorC :: CAbsRule -> String
prDestructorC (c,cs) = unlines [ 
  c ++ "::~" ++ c ++"()",
  "{",
  unlines ["  delete(" ++ cv ++ ");" | (_,isPointer,cv) <- cs, isPointer],
  "}"
  ]
