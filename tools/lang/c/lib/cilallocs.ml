(* Copyright (c) 2011--14,
 *  Stephen Kell        <stephen.kell@cl.cam.ac.uk>
 *
 * with portions taken from logwrites.ml, which is 
 *
 * Copyright (c) 2001-2002, 
 *  George C. Necula    <necula@cs.berkeley.edu>
 *  Scott McPeak        <smcpeak@cs.berkeley.edu>
 *  Wes Weimer          <weimer@cs.berkeley.edu>
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 * 1. Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 *
 * 3. The names of the contributors may not be used to endorse or promote
 * products derived from this software without specific prior written
 * permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
 * IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 * PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
 * OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 *)


open Unix
open List
open Str
open Map
open Pretty
open Cil
module NamedTypeMap = Map.Make(String)

(* Module-ify Cil.typSig *)
module CilTypeSig = struct
   type t = Cil.typsig
   let compare ts1 ts2 = String.compare (Pretty.sprint 80 (d_typsig () ts1)) (Pretty.sprint 80 (d_typsig () ts2))
end

module UniqtypeMap = Map.Make(CilTypeSig)

let debug_print lvl s = 
  try begin 
    let levelString = (Sys.getenv "DEBUG_CC")
    in
    let level = int_of_string levelString
    in
    if level >= lvl then output_string Pervasives.stderr s else ()
  end with Not_found -> () | Failure(_) -> ()

(* HACKed realpath for now: *)
let abspath f =
   if String.get f 0 = '/' then f else (getcwd ()) ^ "/" ^ f

(* stolen from StackOverflow:  http://stackoverflow.com/questions/1584758/
   -- eventually want to change to use Ocaml Batteries Included *)
let trim str =   if str = "" then "" else   let search_pos init p next =
    let rec search i =
      if p i then raise(Failure "empty") else
      match str.[i] with
      | ' ' | '\n' | '\r' | '\t' -> search (next i)
      | _ -> i
    in
    search init   in   let len = String.length str in   try
    let left = search_pos 0 (fun i -> i >= len) (succ)
    and right = search_pos (len - 1) (fun i -> i < 0) (pred)
    in
    String.sub str left (right - left + 1)   with   | Failure "empty" -> "" ;;

let rec canonicalizeBaseTypeStr s = 
 (* 'generated' from a table maintained in srk's libcxxgen  *)
if (s = "signed char" || s = "char" || s = "char signed" ||  false) then "signed char"
else if (s = "unsigned char" || s = "char unsigned" ||  false) then "unsigned char"
else if (s = "short int" || s = "short" || s = "int short" ||  false) then "short int"
else if (s = "short unsigned int" || s = "unsigned short" || s = "short unsigned" || s = "unsigned short int" || s = "int unsigned short" || s = "int short unsigned" || s = "unsigned int short" || s = "short int unsigned" ||  false) then "short unsigned int"
else if (s = "int" || s = "signed" || s = "signed int" || s = "int signed" ||  false) then "int"
else if (s = "unsigned int" || s = "unsigned" || s = "int unsigned" ||  false) then "unsigned int"
else if (s = "long int" || s = "long" || s = "int long" || s = "signed long int" || s = "int signed long" || s = "int long signed" || s = "long signed int" || s = "signed int long" || s = "long signed" || s = "signed long" ||  false) then "long int"
else if (s = "unsigned long int" || s = "int unsigned long" || s = "int long unsigned" || s = "long unsigned int" || s = "unsigned int long" || s = "long unsigned" || s = "unsigned long" ||  false) then "unsigned long int"
else if (s = "long long int" || s = "long long" || s = "long int long" || s = "int long long" || s = "long long signed" || s = "long signed long" || s = "signed long long" || s = "long long int signed" || s = "long long signed int" || s = "long signed long int" || s = "signed long long int" || s = "long int long signed" || s = "long int signed long" || s = "long signed int long" || s = "signed long int long" || s = "int long long signed" || s = "int long signed long" || s = "int signed long long" || s = "signed int long long" ||  false) then "long long int"
else if (s = "long long unsigned int" || s = "long long unsigned" || s = "long unsigned long" || s = "unsigned long long" || s = "long long int unsigned" || s = "long unsigned long int" || s = "unsigned long long int" || s = "long int long unsigned" || s = "long int unsigned long" || s = "long unsigned int long" || s = "unsigned long int long" || s = "int long long unsigned" || s = "int long unsigned long" || s = "int unsigned long long" || s = "unsigned int long long" ||  false) then "long long unsigned int"
else if (s = "float" ||  false) then "float"
else if (s = "double" ||  false) then "double"
else if (s = "long double" || s = "double long" ||  false) then "long double"
else if (s = "bool" ||  false) then "bool"
else if (s = "wchar_t" ||  false) then "wchar_t"
  else s

(* WORKAROUND for CIL's anonymous structure types: 
   we undo the numbering (set to 1) and hope for the best. *)
let hackTypeName s = (*if (string_match (regexp "__anon\\(struct\\|union\\|enum\\)_.*_[0-9]+$") s 0)
   then Str.global_replace (Str.regexp "_[0-9]+$") "_1" s
   else *) s

let baseTypeStr ts = 
   let rawString = match ts with 
     TInt(kind,attrs) -> (Pretty.sprint 80 (d_ikind () kind))
   | TFloat(kind,attrs) -> (Pretty.sprint 80 (d_fkind () kind))
   | TBuiltin_va_list(attrs) -> "__builtin_va_list"
   | _ -> raise(Failure ("bad base type: " ^ (Pretty.sprint 80 (Pretty.dprintf "%a" d_type ts))))
   in 
   Str.global_replace (Str.regexp "[. /-]") "_" (canonicalizeBaseTypeStr (trim rawString))

let rec barenameFromSig ts = 
 let rec labelledArgTs ts startAt =
   match ts with
     [] -> ""
  | t :: morets -> 
      let remainder = (labelledArgTs morets (startAt + 1))
      in
      "__ARG" ^ (string_of_int startAt) ^ "_" ^ (barenameFromSig t) ^ remainder
 in
 match ts with
   TSArray(tNestedSig, optSz, attrs) -> "__ARR" ^ (match optSz with Some(s) -> (string_of_int (i64_to_int s)) | None -> "0") ^ "_" ^ (barenameFromSig tNestedSig)
 | TSPtr(tNestedSig, attrs) -> "__PTR_" ^ (barenameFromSig tNestedSig)
 | TSComp(isSpecial, name, attrs) -> (hackTypeName name)
 | TSFun(returnTs, Some(argsTss), false, attrs) -> 
       "__FUN_FROM_" ^ (labelledArgTs argsTss 0) ^ "__FUN_TO_" ^ (barenameFromSig returnTs)
 | TSFun(returnTs, Some(argsTss), true, attrs) -> 
       "__FUN_FROM_" ^ (labelledArgTs argsTss 0) ^ "__VA___FUN_TO_" ^ (barenameFromSig returnTs)
 | TSFun(returnTs, None, _, attrs) -> 
        "__FUN_FROM___VA___FUN_TO_" ^ (barenameFromSig returnTs)
 | TSEnum(enumName, attrs) -> enumName
 | TSBase(TVoid(attrs)) -> "void"
 | TSBase(tbase) -> baseTypeStr tbase

let rec dwarfidlFromSig ts = 
 let rec dwarfidlLabelledArgTs ts startAt =
   match ts with
     [] -> ""
  |  [t] -> dwarfidlFromSig t
  | t :: morets -> 
      let remainder = (dwarfidlLabelledArgTs morets (startAt + 1))
      in
      (dwarfidlFromSig t) ^ ", " ^ remainder
 in
 match ts with
   TSArray(tNestedSig, optSz, attrs)
     -> "array_type [type = " ^ (dwarfidlFromSig tNestedSig) ^ "] {" 
        ^ (match optSz with Some(s) -> ("subrange_type [upper_bound = " ^ (string_of_int (i64_to_int s)) ^ "]") | None -> "") ^ "}"
 | TSPtr(tNestedSig, attrs) -> "pointer_type [type = " ^ (dwarfidlFromSig tNestedSig) ^ "] {}" 
 | TSComp(isSpecial, name, attrs) -> (hackTypeName name)
 | TSFun(returnTs, Some(argsTss), false, attrs) -> 
       "(" ^ (dwarfidlLabelledArgTs argsTss 0) ^ ") => " ^ (dwarfidlFromSig returnTs)
 | TSFun(returnTs, Some(argsTss), true, attrs) -> 
       "(" ^ (dwarfidlLabelledArgTs argsTss 0) ^ ", ...)" ^ (dwarfidlFromSig returnTs)
 | TSFun(returnTs, None, _, attrs) -> 
        "(...) => " ^ (barenameFromSig returnTs)
 | TSEnum(enumName, attrs) -> enumName
 | TSBase(TVoid(attrs)) -> "unspecified_type"
 | TSBase(tbase) -> baseTypeStr tbase

let userTypeNameToBareName s = Str.global_replace (Str.regexp "[. /-]") "_" (canonicalizeBaseTypeStr (trim s))

let symnameFromSig ts = "__uniqtype_" ^ "" ^ "_" ^ (barenameFromSig ts)

(* CIL doesn't give us a const void * type builtin, so we define one. *)
let voidConstPtrType = TPtr(TVoid([Attr("const", [])]),[])

(* Returns true if the given lvalue offset ends in a bitfield access. *) 
let rec is_bitfield lo = match lo with
  | NoOffset -> false
  | Field(fi,NoOffset) -> not (fi.fbitfield = None)
  | Field(_,lo) -> is_bitfield lo
  | Index(_,lo) -> is_bitfield lo 

(* Return an expression that evaluates to the address of the given lvalue.
 * For most lvalues, this is merely AddrOf(lv). However, for bitfields
 * we do some offset gymnastics. 
 *)
let addr_of_lv (lh,lo) = 
  if is_bitfield lo then begin
    (* we figure out what the address would be without the final bitfield
     * access, and then we add in the offset of the bitfield from the
     * beginning of its enclosing comp *) 
    let rec split_offset_and_bitfield lo = match lo with 
      | NoOffset -> failwith "trumptr: impossible" 
      | Field(fi,NoOffset) -> (NoOffset,fi)
      | Field(e,lo) ->  let a,b = split_offset_and_bitfield lo in 
                        ((Field(e,a)),b)
      | Index(e,lo) ->  let a,b = split_offset_and_bitfield lo in
                        ((Index(e,a)),b)
    in 
    let new_lv_offset, bf = split_offset_and_bitfield lo in
    let new_lv = (lh, new_lv_offset) in 
    let enclosing_type = TComp(bf.fcomp, []) in 
    let bits_offset, bits_width = 
      bitsOffset enclosing_type (Field(bf,NoOffset)) in
    let bytes_offset = bits_offset / 8 in 
    let lvPtr = mkCast ~e:(mkAddrOf (new_lv)) ~newt:(charPtrType) in
    (BinOp(PlusPI, lvPtr, (integer bytes_offset), ulongType))
  end else (AddrOf (lh,lo))

(* This effectively embodies our "default specification" for C code
 * -- it controls what we assert in "__is_a" tests, and
 * needs to mirror what we record for allocation sites in dumpallocs *)
let rec getConcreteType ts =
 match ts with
   TSArray(tsig, optSz, attrs) -> getConcreteType tsig
 | TSPtr(tsig, attrs) -> TSPtr(getConcreteType tsig, []) (* stays a pointer, but discard attributes *)
 | TSComp(isSpecial, name, attrs) -> TSComp(isSpecial, name, [])
 | TSFun(returnTs, maybeArgsTss, isSpecial, attrs) -> TSFun(returnTs, maybeArgsTss, isSpecial, [])
 | TSEnum(enumName, attrs) -> TSEnum(enumName, [])
 | TSBase(TVoid(attrs)) -> TSBase(TVoid([]))
 | TSBase(TInt(kind,attrs)) -> TSBase(TInt(kind, []))
 | TSBase(TFloat(kind,attrs)) -> TSBase(TFloat(kind, []))
 | _ -> ts

 
 let matchIgnoringLocation g1 g2 = match g1 with 
    GType(ti, loc) ->        begin match g2 with GType(ti2, _)        -> ti = ti2 | _ -> false end
  | GCompTag(ci, loc) ->     begin match g2 with GCompTag(ci2, _)     -> ci = ci2 | _ -> false end
  | GCompTagDecl(ci, loc) -> begin match g2 with GCompTagDecl(ci2, _) -> ci = ci2 | _ -> false end
  | GEnumTag(ei, loc) ->     begin match g2 with GEnumTag(ei2, _)     -> ei = ei2 | _ -> false end
  | GEnumTagDecl(ei, loc) -> begin match g2 with GEnumTagDecl(ei2, _) -> ei = ei2 | _ -> false end
  | GVarDecl(vi, loc) ->     begin match g2 with GVarDecl(vi2, loc)   -> vi = vi2 | _ -> false end
  | GVar(vi, ii, loc) ->     begin match g2 with GVar(vi2, ii2, loc)  -> ((vi = vi2) (* and (ii = ii2) *)) | _ -> false end
  | GFun(f, loc) ->          begin match g2 with GFun(f2, loc)        -> f  = f2  | _ -> false end
  | GAsm(s, loc) ->          begin match g2 with GAsm(s2, loc)        -> s  = s2  | _ -> false end
  | GPragma(a, loc) ->       begin match g2 with GPragma(a2, loc)     -> a  = a2  | _ -> false end
  | GText(s) ->              begin match g2 with GText(s2)            -> s  = s2  | _ -> false end

let isFunction g = match g with
  GFun(_, _) -> true
| _ -> false

let newGlobalsList globals toAdd insertBeforePred = 
  let (preList, postList) = 
      let rec buildPre l accumPre = match l with 
          [] -> (accumPre, [])
       |  x::xs -> if (insertBeforePred x) then (accumPre, x :: xs) else buildPre xs (accumPre @ [x])
      in 
      buildPre globals []
  in
  preList @ toAdd @ postList

let getOrCreateUniqtypeGlobal m typename concreteType globals = 
  try 
      let found = UniqtypeMap.find concreteType m
      in
      let foundVar = match found with 
        GVarDecl(v, i) -> v
      | _ -> raise(Failure "unexpected state")
      in 
      (m, foundVar, globals)
  with Not_found -> 
     let newGlobal = 
       let tempGlobal = makeGlobalVar typename (TInt(IInt, [])); 
       in 
       tempGlobal.vstorage <- Extern;
       tempGlobal.vattr <- [Attr("weak", [])];
       tempGlobal
     in
     let newGlobalVarInfo = GVarDecl(newGlobal, {line = -1; file = "BLAH FIXME"; byte = 0})
     in 
     let newMap = (UniqtypeMap.add concreteType newGlobalVarInfo m)
     in 
     let newGlobals = newGlobalsList globals [newGlobalVarInfo] isFunction
     in
     (newMap, newGlobal, newGlobals)


let findCompDefinitionInFile isStruct name wholeFile = 
    let rec findCompGlobal iss n globals = 
        match globals with
            []       -> None
        |   g :: gs  -> begin match g with
                GCompTag(ci, _) -> if ci.cstruct = isStruct && ci.cname = name then Some(g) else findCompGlobal iss n gs
              | _ -> findCompGlobal iss n gs
            end
    in
    findCompGlobal isStruct name wholeFile.globals

let rec tsIsUndefinedType ts wholeFile = 
    let rec anyTsIsUndefined tss = match tss with
        []          -> false
      | ts1 :: more -> (tsIsUndefinedType ts1 wholeFile) || (anyTsIsUndefined more)
    in
    match ts with
        TSArray(tsig, optSz, attrs)                 -> tsIsUndefinedType tsig wholeFile
    |   TSPtr(tsig, attrs)                          -> tsIsUndefinedType tsig wholeFile
    |   TSComp(isStruct, name, attrs)               -> (findCompDefinitionInFile isStruct name wholeFile) = None
    |   TSFun(returnTs, maybeArgsTss, isVarargs, attrs)  -> begin
            tsIsUndefinedType returnTs wholeFile || match maybeArgsTss with
                None -> false
              | Some(argsTss) -> anyTsIsUndefined argsTss
        end
    |   _                                           -> false