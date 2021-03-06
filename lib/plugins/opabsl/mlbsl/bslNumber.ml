(*
    Copyright © 2011, 2012 MLstate

    This file is part of Opa.

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*)
##extern-type int64 = Int64.t

##extern-type int32 = Int32.t

exception Not_implemented of string
exception BslNumberError of string

##module Int \ bsl_int

##register max_int : int
  let max_int =
    let is_32 = (1 lsl 30) = max_int
    in if is_32 then max_int else  1 lsl 53;;

##register of_string : string -> int
  let of_string s =
    try
      Pervasives.int_of_string s
    with
    | Failure "int_of_string" ->
        failwith (Printf.sprintf "Error in Int.of_string: %S is not an integer." s)

##register of_string_opt : string -> option(int)
let of_string_opt s =
  try
    Some (Pervasives.int_of_string s)
  with
  | Failure "int_of_string" -> None

##register of_float : float -> int
  let of_float = Pervasives.int_of_float

(* Bitwise operations *)
##register op_land \ `Pervasives.(land)` : int, int -> int
##register op_lor \ `Pervasives.(lor)` : int, int -> int
##register op_lxor \ `Pervasives.(lxor)` : int, int -> int
##register op_lnot \ `Pervasives.lnot` : int -> int
##register op_lsl \ `Pervasives.(lsl)` : int, int -> int
##register op_lsr \ `Pervasives.(lsr)` : int, int -> int
##register op_asr \ `Pervasives.(asr)` : int, int -> int

##register leq: int, int -> bool
let leq (a:int) (b:int) = a <= b

##register geq: int, int -> bool
let geq (a:int) (b:int) = a >= b


##register ordering: int, int -> opa[Order.ordering]
let ordering (a:int) (b:int) =
  if a < b then BslPervasives.ord_result_lt
  else if a==b then BslPervasives.ord_result_eq
  else BslPervasives.ord_result_gt

##endmodule

##module BslInt64

##register catch : ( -> 'a) -> opa[outcome('a,string)]
let catch f =
  try
    BslUtils.create_outcome (`success (f()))
  with exn ->
    BslUtils.create_outcome (`failure (Printexc.to_string exn))

##register add \ `Int64.add` : int64, int64 -> int64
##register sub \ `Int64.sub` : int64, int64 -> int64
##register mul \ `Int64.mul` : int64, int64 -> int64
##register div \ `Int64.div` : int64, int64 -> int64
##register rem \ `Int64.rem` : int64, int64 -> int64
##register pred \ `Int64.pred` : int64 -> int64
##register succ \ `Int64.succ` : int64 -> int64
##register logand \ `Int64.logand` : int64, int64 -> int64
##register logor \ `Int64.logor` : int64, int64 -> int64
##register logxor \ `Int64.logxor` : int64, int64 -> int64
##register lognot \ `Int64.lognot` : int64 -> int64
##register shift_left \ `Int64.shift_left` : int64, int -> int64
##register shift_right \ `Int64.shift_right` : int64, int -> int64
##register shift_right_logical \ `Int64.shift_right_logical` : int64, int -> int64
##register of_int \ `Int64.of_int` : int -> int64
##register of_int_signed \ `Int64.of_int` : int -> int64
##register to_int \ `Int64.to_int` : int64 -> int
##register to_int_signed \ `Int64.to_int` : int64 -> int
##register of_string \ `Int64.of_string` : string -> int64

##register of_string_radix : string, int -> int64
let of_string_radix (s:string) (radix:int) : int64 =
  let tab (c:char) : int =
    match c with
    | '0' -> 0 | '1' -> 1 | '2' -> 2 | '3' -> 3 | '4' -> 4 | '5' -> 5 | '6' -> 6 | '7' -> 7 | '8' -> 8 | '9' -> 9
    | 'a' -> 10 | 'b' -> 11 | 'c' -> 12 | 'd' -> 13 | 'e' -> 14 | 'f' -> 15
    | 'A' -> 10 | 'B' -> 11 | 'C' -> 12 | 'D' -> 13 | 'E' -> 14 | 'F' -> 15
    | _ -> raise (BslNumberError (Printf.sprintf "Int64.of_string: bad character %c" c))
  in
  if (radix < 2 || radix > 16) then raise (BslNumberError (Printf.sprintf "Int64.of_string: bad radix %d" radix));
  let x = ref Int64.zero in
  let radix64 = Int64.of_int radix in
  let (sign, istart) = if s.[0] = '-' then (-1L,1) else (1L,0) in
  for i = istart to String.length s - 1 do
    let dig = tab(s.[i]) in
    if dig >= radix then raise (BslNumberError (Printf.sprintf "Int64.of_string: bad digit %d" dig));
    (* TODO: proper check for overflow *)
    x := Int64.add (Int64.mul !x radix64) (Int64.of_int dig)
  done;
  Int64.mul sign !x

##register to_string \ `Int64.to_string` : int64 -> string

##register to_string_radix : int64, int -> string
let to_string_radix (i:int64) (radix:int) : string =
  if (radix < 2 || radix > 16) then raise (BslNumberError (Printf.sprintf "Int64.of_string: bad radix %d" radix));
  if i = 0L then "0"
  else if i = 1L then "1"
  else
    let (sign,i) = if Int64.compare i 0L = (-1) then ("-",Int64.sub 0L i) else ("",i) in
    let strs = "0123456789abcdef" in
    let s = ref [] in
    let radix64 = Int64.of_int radix in
    let i = ref i in
    while !i <> 0L do
      let r = Int64.rem !i radix64 in
      if Int64.compare r radix64 = 1 then raise (BslNumberError "Int64.of_string: bad number");
      s := (strs.[Int64.to_int r])::!s;
      i := Int64.div !i radix64
    done;
    let r = String.create (List.length !s) in 
    let _ = List.fold_left (fun i c -> r.[i] <- c; i+1) 0 !s in
    sign^r

##register op_eq : int64, int64 -> bool
let op_eq i1 i2 = i1 = i2
##register op_ne : int64, int64 -> bool
let op_ne i1 i2 = i1 <> i2
##register op_gt : int64, int64 -> bool
let op_gt i1 i2 = i1 > i2
##register op_ge : int64, int64 -> bool
let op_ge i1 i2 = i1 >= i2
##register op_lt : int64, int64 -> bool
let op_lt i1 i2 = i1 < i2
##register op_le : int64, int64 -> bool
let op_le i1 i2 = i1 <= i2

##register to_int_signed_opt : int64 -> option(int)
let to_int_signed_opt (i64:int64) =
  if op_gt i64 (Int64.of_int max_int) then None
  else Some (Int64.to_int i64)

let max_int64 = Int64.max_int
##register max_int \ max_int64 : int64

##register is_NaN : int64 -> bool
let is_NaN _ = false

##endmodule

##module Float

  (* transforms the string in a format compatible with the same function
   * in jsbsl:
   * - same NaN, Infinity
   * - decimal point when not in scientific notation: 1.0, 1e-88
   * - no -0.0 *)
##register to_string : float -> string
  let to_string f =
    match classify_float f with
      | FP_nan -> "NaN"
      | FP_infinite -> if f > 0. then "Infinity" else "-Infinity"
      | FP_zero -> "0.0"
      | FP_subnormal (* what to do here for compatibility with js ? *)
      | FP_normal ->
          let s = string_of_float f in
          let last = String.length s - 1 in
          if s.[last] = '.' then s ^ "0"
          else s

##register to_formatted_string : bool, option(int), float -> string
  (** A function to format float printing
      @param always_dot [true] when the numbers should always have a decimal point: '1.00', for instance
                        [false] means that 1. will be printed as '1'
      @param decimals_option [None] means the default precision will be displayed
                             [Some _] the number of decimals that should appear after the dot
                             please note that if you say 2 decimals but always_dot is false
                             2. will be printed 2, not 2.00
                             (the number of decimals is used only if you have a decimal point to begin with)
      @param f The float you want to print
  *)
  let to_formatted_string always_dot decimals_option f =
    match classify_float f with
      | FP_nan -> "NaN"
      | FP_infinite -> if f > 0. then "Infinity" else "-Infinity"
      | FP_zero ->
          (match always_dot, decimals_option with
           | false, _ -> "0"
           | true, None -> "0.0"
           | true, Some decimals ->
               assert (decimals >= 0);
               Printf.sprintf "%.*f" decimals 0.)
      | FP_subnormal (* same remark as above *)
      | FP_normal ->
          let is_an_int_before_truncating =
            match modf f with
            | (0.,_) -> true
            | _ -> false in
          match decimals_option with
          | None ->
              if is_an_int_before_truncating then
                let int = string_of_int (int_of_float f) in
                if always_dot then int ^ ".0" else int
              else
                string_of_float f
          | Some decimals ->
              (* here we have a choice: either 4.02 with 1 decimal is displayed as 4.0
                 or it is displayed as 4 (when we don't want the decimal point)

                 here, we choose the first solution, but you would just have to replace
                 is_an_int_before_truncating by is_an_int_after_troncating to have
                 the opposite (and you would have to change the js code to so too)

                 let int = int_of_float in
                 let is_an_int_after_troncating =
                 let p =  (10. ** (float)decimals) in (* clean me *)
                 (int)(p *. f) mod (int)p = 0 in *)
              match always_dot, is_an_int_before_truncating with
              | false,true  -> string_of_int (int_of_float f)
              | _ -> Printf.sprintf "%.*f" decimals f

##register of_string : string -> float
let of_string s = Pervasives.float_of_string s

##register of_string_opt : string -> option(float)
let of_string_opt s =
  try
    Some (Pervasives.float_of_string s)
  with
  | Failure "float_of_string" -> None

##register of_int : int -> float
  let of_int = float_of_int

##register ceil : float -> float
  let ceil = Pervasives.ceil

##register floor : float -> float
  let floor = Pervasives.floor

##register leq: float, float -> bool
let leq (a:float) (b:float) = a <= b

##register lt: float, float -> bool
let lt (a:float) (b:float) = a < b

##register eq: float, float -> bool
let eq (a:float) (b:float) = a = b

##register geq: float, float -> bool
let geq (a:float) (b:float) = a >= b

##register gt: float, float -> bool
let gt (a:float) (b:float) = a > b

##register neq: float, float -> bool
let neq (a:float) (b:float) = a <> b

##register comparison: float, float -> opa[Order.comparison]
let comparison (a:float) (b:float) =
  if a = a && b = b then (*Handle [nan]*)
    if a < b then BslPervasives.comp_result_lt
    else if a = b then BslPervasives.comp_result_eq
    else BslPervasives.comp_result_gt
  else
    BslPervasives.comp_result_neq

##register round : float -> int
  let round v = int_of_float (Base.round 0 v)

##register embed_int64_le : int64 -> string
let embed_int64_le i64 =
  let s = "        " in
  s.[7] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 56) 0xffL)));
  s.[6] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 48) 0xffL)));
  s.[5] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 40) 0xffL)));
  s.[4] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 32) 0xffL)));
  s.[3] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 24) 0xffL)));
  s.[2] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 16) 0xffL)));
  s.[1] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 8 ) 0xffL)));
  s.[0] <- (Char.chr (Int64.to_int (Int64.logand (                          i64   ) 0xffL)));
  s

##register embed_float_le : float -> string
let embed_float_le f =
  let i64 = Int64.bits_of_float f in
  embed_int64_le i64 (* TODO: remove this duplicated code *)

##register embed_int64_be : int64 -> string
let embed_int64_be i64 =
  let s = "        " in
  s.[0] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 56) 0xffL)));
  s.[1] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 48) 0xffL)));
  s.[2] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 40) 0xffL)));
  s.[3] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 32) 0xffL)));
  s.[4] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 24) 0xffL)));
  s.[5] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 16) 0xffL)));
  s.[6] <- (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical i64 8 ) 0xffL)));
  s.[7] <- (Char.chr (Int64.to_int (Int64.logand (                          i64   ) 0xffL)));
  s

##register embed_float_be : float -> string
let embed_float_be f =
  let i64 = Int64.bits_of_float f in
  embed_int64_be i64

##register unembed_int64_le: string, int -> int64
let unembed_int64_le s i =
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i+7])) 56) 0xff00000000000000L)
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i+6])) 48) 0x00ff000000000000L)
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i+5])) 40) 0x0000ff0000000000L)
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i+4])) 32) 0x000000ff00000000L)
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i+3])) 24) 0x00000000ff000000L)
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i+2])) 16) 0x0000000000ff0000L)
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i+1]))  8) 0x000000000000ff00L)
               (Int64.logand (                 (Int64.of_int (Char.code s.[i  ]))   ) 0x00000000000000ffL))))))))

##register unembed_float_le: string, int -> float
let unembed_float_le s i =
  Int64.float_of_bits(unembed_int64_le s i)

##register unembed_int64_be: string, int -> int64
let unembed_int64_be s i =
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i  ])) 56) 0xff00000000000000L)
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i+1])) 48) 0x00ff000000000000L)
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i+2])) 40) 0x0000ff0000000000L)
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i+3])) 32) 0x000000ff00000000L)
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i+4])) 24) 0x00000000ff000000L)
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i+5])) 16) 0x0000000000ff0000L)
  (Int64.logor (Int64.logand (Int64.shift_left (Int64.of_int (Char.code s.[i+6]))  8) 0x000000000000ff00L)
               (Int64.logand (                 (Int64.of_int (Char.code s.[i+7]))   ) 0x00000000000000ffL))))))))

##register unembed_float_be: string, int -> float
let unembed_float_be s i =
  Int64.float_of_bits(unembed_int64_be s i)

##register dump : string -> string
let dump _ = raise (Not_implemented "dump")

##register is_int_NaN   \ `(fun _ -> false)`        : int -> bool

##endmodule

##module Math

##register sqrt_f : float -> float
  let sqrt_f = Pervasives.sqrt

##register sqrt_i : int -> int
  let sqrt_i n = Pervasives.int_of_float (Pervasives.sqrt (Pervasives.float_of_int n))

##register log : float -> float
  let log = Pervasives.log

##register exp : float -> float
  let exp = Pervasives.exp

##register abs_i : int -> int
  let abs_i = Pervasives.abs

##register abs_f : float -> float
  let abs_f = Pervasives.abs_float

##register ceil : float -> float
  let ceil = Pervasives.ceil

##register floor : float -> float
  let floor = Pervasives.floor

##register sin : float -> float
  let sin = Pervasives.sin

##register cos : float -> float
  let cos = Pervasives.cos

##register tan : float -> float
  let tan = Pervasives.tan

##register asin : float -> float
  let asin = Pervasives.asin

##register acos : float -> float
  let acos = Pervasives.acos

##register atan : float -> float
  let atan = Pervasives.atan

  (* keep the coerse `x : float', otherwise isNaN(0.0 /. 0.0) is false *)
##register isNaN : float -> bool
  let isNaN = (fun (x : float) -> not ( x = x ))

##register is_infinite : float -> bool
  let is_infinite f = classify_float f = FP_infinite

##register is_normal : float -> bool
  let is_normal f =
    match classify_float f with
      | FP_normal | FP_subnormal | FP_zero -> true
      | _ -> false

##endmodule

##module Random

  let max_int_for_random_int = 1 lsl 30

##register int : int -> int
  let int v =
    if v<max_int_for_random_int then Random.int v else Int64.to_int (Random.int64 (Int64.of_int v))

##register float : float -> float
  let float v = Random.float v

##register random_init : -> void
  let random_init() =
    Random.self_init()

##register generic_string : string, int -> string
  let generic_string chars len =
    let s = String.create len in
    for i =  0 to len - 1 do
      s.[i] <- chars.[Random.int (String.length chars)]
    done;
    s

##register string : int -> string
  let string len =
    let chars = "abcdefghijklmnopqrstuvwxyz" in
    generic_string chars len

##register base64 : int -> string
let base64 len =
  let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" in
  generic_string chars len

##register base64_url : int -> string
let base64_url len =
  let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_" in
  generic_string chars len

##endmodule
