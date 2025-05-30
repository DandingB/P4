(* Compiling a library apperently finds warnings that was not there before idk.
   I have not changed anything so, ignore specific warnings with this *)
[@@@ocaml.warning "-9"]
[@@@ocaml.warning "-27"]

open Ast

type value =
  | Vnone
  | Vbool of bool
  | Vnum of float
  | Vstring of string
  | Varray of value array
  | Vmatrix of value array array

(* Local variables (function parameters and local variables introduced
  by assignments) are stored in a hash table that is passed to the
  following OCaml functions as parameter `ctx`. *)

type ctx = (string, value) Hashtbl.t
let functions =  (Hashtbl.create 17 : (string, ident list* stmt) Hashtbl.t)

exception Return of value

(* This function is used to check if a number is an integer. *)
(* It is used to format the output of numbers correctly. *)

(* This function is used to check if a number has a decimal part. *)
(* It is used to format the output of numbers correctly. *)

let has_decimal_part x =
  x <> floor x  

let is_false v = 
  if v = Vnone then true 
  else if v = Vbool false then true 
  else if v = Vnum 0. then true 
  else if v = Vstring "" then true 
  else if v = Varray [||] then true 
  else if v = Vmatrix [||] then true 
  else false

let is_true v = not (is_false v)

let rec to_string e =
  match e with
  | Vnone -> Vstring "None"
  | Vnum n ->
    if has_decimal_part n 
    then Vstring(Printf.sprintf "%f" n)
    else Vstring(Printf.sprintf "%d" (int_of_float n))
  | Vbool n -> Vstring(Printf.sprintf "%B" n)
  | Vstring n -> Vstring(Printf.sprintf "%s" n)
  | Varray arr ->
    (* Get array length *)
    let arrLen = Array.length arr in
    (* If length == 0 just return empty array [] *)
    if arrLen == 0 then Vstring "[]"
    else 
      (* Map all elements to string representation by calling to_string recursivly *)
      let elements = Array.mapi (fun i v ->
        let str = match to_string v with
          | Vstring s -> s
          | _ -> failwith "Expected string in to_string"
        in
        (* If it is the last value we do not at a comma at the end *)
        if i == arrLen - 1 then str else str ^ ", "
      ) arr in
      (* Concat all the elements *)
      Vstring ("[" ^ Array.fold_left (^) "" elements ^ "]")
  | Vmatrix matrix ->
    (* Get matrix length *)
    let matrixLen = Array.length matrix in
    (* If length == 0 just return empty array [] *)
    if matrixLen == 0 then Vstring "[]"
    else 
      (* Map all elements to string representation by calling to_string recursivly *)
      let elements = Array.mapi (fun i arr ->
        let str = match to_string (Varray arr) with
          | Vstring s -> s
          | _ -> failwith "Expected string in to_string"
        in
        (* If it is the last value we do not at a comma at the end *)
        if i == matrixLen - 1 then str else str ^ ",\n"
      ) matrix in
      (* Concat all the elements *)
      Vstring ("[" ^ Array.fold_left (^) "" elements ^ "]")

let print_value e = 
  let v1 = to_string e in
  match v1 with
  | Vstring n -> Printf.printf "%s" n
  | _ -> failwith "Unsupported print"

let get_datatype v = 
  begin match v with 
  | Vnone -> "None"
  | Vbool _ -> "boolean"
  | Vnum _ -> "number"
  | Vstring _ -> "string"
  | Varray _ -> "array"
  | Vmatrix _ -> "matrix"
  end

let rec expr ctx = function 
  | Ecst (Cnone) -> Vnone
  | Ecst (Cnum n) -> Vnum n
  | Ecst (Cbool n) -> Vbool n
  | Ecst (Cstring n) -> Vstring n
  | Earray l -> 
    let arr = Array.of_list (List.map (expr ctx) l) in
    Varray arr
  | Eget (e1, e2) -> 
    let v1 = expr ctx e1 in
    let v2 = expr ctx e2 in
    begin match v1, v2 with
      | Varray arr, Vnum index -> 
        if index < 0.0 || index >= float (Array.length arr) then failwith (Printf.sprintf "Index '%d' out of bounds: length is %d " (int_of_float index) (Array.length arr))
        else arr.(int_of_float index)
      | Vstring s, Vnum index -> 
        if index < 0.0 || index >= float (String.length s) then failwith (Printf.sprintf "Index '%d' out of bounds: length is %d " (int_of_float index) (String.length s))
        else Vstring (String.make 1 (s.[int_of_float index]))
      | _ -> failwith "Wrong expression types"
    end
  | Egetmatrix (e1,e2,e3) ->
    let v1 = expr ctx e1 in
    let v2 = expr ctx e2 in
    let v3 = expr ctx e3 in
    begin match v1, v2, v3 with 
        | Vmatrix matrix, Vnum row, Vnum col -> 
          if row < 0.0 || row >= float (Array.length matrix) || col < 0.0 || col >= float (Array.length matrix.(0)) then
            failwith (Printf.sprintf "Index [%d, %d] out of bounds: dimensions are %dx%d " (int_of_float row) (int_of_float col) (Array.length matrix) (Array.length matrix.(0)))
          else matrix.(int_of_float row).(int_of_float col)
        | _ -> failwith "Wrong expression types"
   end
  (* Length of array or string *)
  | Elength e1 -> 
    let v1 = expr ctx e1 in
    begin match v1 with
      | Varray arr -> Vnum (float (Array.length arr))
      | Vstring s -> Vnum (float (String.length s))
      | _ -> failwith "The length operator can only be used on Arrays and Strings."
    end
  | Ebinop (Badd | Bsub | Bmul | Bdiv | Blt | Beq | Bgt | Bge | Ble | Bneq | Bmod | Bpow  as op, e1, e2) ->
      let v1 = expr ctx e1 in
      let v2 = expr ctx e2 in
      begin match op, v1, v2 with
        | Badd, Vnum n1, Vnum n2 -> Vnum (n1 +. n2)
        | Badd, Vstring n1, Vstring n2  -> Vstring (n1 ^ n2)
        | Badd, Varray n1, Varray n2 -> Varray (Array.append n1 n2)
        | Badd, Vmatrix m1, Vmatrix m2 ->
          (* Helper function to transpose a matrix *)
          let transpose matrix =
            Array.init (Array.length matrix.(0)) (fun i ->
              Array.map (fun row -> row.(i)) matrix
            )
          in
      
          (* Get dimensions of both matrices *)
          let m1_rows = Array.length m1 in
          let m1_cols = Array.length m1.(0) in
          let m2_rows = Array.length m2 in
          let m2_cols = Array.length m2.(0) in
      
          (* Check if matrices can be transformed to match dimensions *)
          let (m1_final, m2_final) =
            if m1_rows = m2_rows && m1_cols = m2_cols then
              (* Standard case: dimensions already match *)
              (m1, m2)
            else if (m1_rows = 1 || m1_cols = 1) && (m2_rows = 1 || m2_cols = 1) then
              (* 
              We check if the m1 dimensions match the transposed m2 dimensions,
              and we make sure that both m1 and m2 are vectors (at least one row or column is 1).
              *)
              if m1_rows = m2_cols && m1_cols = m2_rows then
                (* Transform m2 to match m1's dimensions *)
                (m1, transpose m2)
              else
                failwith "Vector dimensions do not match for addition"
            else
              failwith "Matrix dimensions do not match for addition"
          in
      
          (* We make sure that the final matrix dimensions are the same *)
          if Array.length m1_final <> Array.length m2_final ||
             Array.length m1_final.(0) <> Array.length m2_final.(0) then
            failwith "Matrix dimensions do not match for addition"
          else
            (* We create a new matrix with the same dimensions.
               We do this by looping over the first matrix, then the second and adding each element in the rows.
               We end up returning the new matrix.
            *)
            let result = Array.mapi (fun i row1 ->
              Array.mapi (fun j val1 ->
                match val1, m2_final.(i).(j) with
                | Vnum n1, Vnum n2 -> Vnum (n1 +. n2)
                | _ -> failwith "Matrix addition only supports numeric values"
              ) row1
            ) m1_final in
            Vmatrix result
        | Badd, _, _ -> 
            let s1 = match to_string v1 with Vstring s -> s | _ -> failwith "Expected string" in
            let s2 = match to_string v2 with Vstring s -> s | _ -> failwith "Expected string" in
            Vstring(s1 ^ s2)
        | Bsub, Vnum n1, Vnum n2 -> Vnum (n1 -. n2)
        | Bmul, Vnum n1, Vnum n2 -> Vnum (n1 *. n2)
        | Bmul, Vmatrix m1, Vmatrix m2 ->
          (* Helper function to transpose a Vmatrix (vector in our case) *)
          let transpose matrix =
            Array.init (Array.length matrix.(0)) (fun i ->
              Array.map (fun row -> row.(i)) matrix
            )
          in
      
          (* Get dimensions of both matrices *)
          let m1_rows = Array.length m1 in
          let m1_cols = Array.length m1.(0) in
          let m2_rows = Array.length m2 in
          let m2_cols = Array.length m2.(0) in
      
          (* Check if vectors can be transformed to match multiplication dimensions *)
          let (m1_final, m2_final) =
            if m1_cols = m2_rows then
              (* Standard case, dimensions already match *)
              (m1, m2)
            else if m1_cols = m2_cols && (m2_rows = 1 || m2_cols = 1) then
              (* m2 is a vector: transpose m2 to match m1's orientation *)
              (m1, transpose m2)
            else if m1_rows = m2_rows && (m1_rows = 1 || m1_cols = 1) then
              (* m1 is a vector: transpose m1 to match m2's orientation *)
              (transpose m1, m2)
            else
              (* Cannot fix dimensions even with transposing *)
              failwith "Matrix dimensions cannot be made compatible for multiplication"
          in
      
          (* Compute the resulting matrix *)
          (* We do this by creating an array with the length corresponding to the rows of matrix 1.
             It will contain arrays inside with a length corresponding to the columns of matrix 2. *)
          let result_rows = Array.length m1_final in
          let result_cols = Array.length m2_final.(0) in
          let common_dim = Array.length m1_final.(0) in
      
          let result = Array.init result_rows (fun i ->
            Array.init result_cols (fun j ->
              (* Compute the dot product of row i in m1_final and column j in m2_final *)
              let dot_product =
                (* 
                  We compute the dot product of row i from m1_final and column j from m2_final.
                  We use Array.fold_left to loop over all common indices (k),
                  starting with an accumulator value of 0.0, and for each step, we:
                  - take the value from m1_final at (i, k) and the value from m2_final at (k, j)
                  - multiply them together
                  - add the product to the accumulator.

                  Array.init common_dim Fun.id generates an array of indices [0; 1; ...; common_dim - 1].
                *)
                Array.fold_left (fun acc k ->
                  match m1_final.(i).(k), m2_final.(k).(j) with
                  (* We add the product of the two values to the accumulator acc *)
                  | Vnum n1, Vnum n2 -> acc +. (n1 *. n2)
                  | _ -> failwith "Matrix multiplication only supports numeric values"
                ) 0.0 (Array.init common_dim Fun.id)
              in
              Vnum dot_product
            )
          ) in
          Vmatrix result
      
        | Bdiv, Vnum n1, Vnum n2 -> Vnum (n1 /. n2)
        | Bmod, Vnum n1, Vnum n2 -> Vnum (mod_float n1 n2)
        | Bpow, Vnum n1, Vnum n2 -> Vnum (n1 ** n2)
        | Blt, Vnum n1, Vnum n2 -> Vbool (n1 < n2)
        | Blt, Vstring s1, Vstring s2 -> Vbool (s1 < s2)
        | Beq, Vnum n1, Vnum n2 -> Vbool (n1 = n2)
        | Beq, Vstring s1, Vstring s2 -> Vbool (s1 = s2)
        | Bgt, Vnum n1, Vnum n2 -> Vbool (n1 > n2)
        | Bgt, Vstring s1, Vstring s2 -> Vbool (s1 > s2)
        | Bge, Vnum n1, Vnum n2 -> Vbool (n1 >= n2)
        | Bge, Vstring s1, Vstring s2 -> Vbool (s1 >= s2)
        | Ble, Vnum n1, Vnum n2 -> Vbool (n1 <= n2)
        | Ble, Vstring s1, Vstring s2 -> Vbool (s1 <= s2)
        | Bneq, Vnum n1, Vnum n2 -> Vbool (n1 != n2)
        | _ , e1, e2 -> failwith (Printf.sprintf "Invalid binary operation. Operand types are '%s' and '%s'" (get_datatype e1) (get_datatype e2))
      end
  (* Binary operations for And and Or *)
  | Ebinop (Band, e1, e2) ->
    Vbool (is_true (expr ctx e1) && is_true (expr ctx e2))
  | Ebinop (Bor, e1, e2) ->
      Vbool (is_true (expr ctx e1) || is_true (expr ctx e2))
  | Eunop (Uneg, e) ->
    let v1 = expr ctx e in
    begin match v1 with
    | Vnum n2 -> Vnum( -.n2)
    | _ -> failwith (Printf.sprintf "Invalid unary operation. Operand type are '%s'" (get_datatype v1))
    end
  | Eunop (Unot, e) ->
      Vbool (is_false (expr ctx e))
    (* When we have an identity we find it in the hastable and return it. *)
  | Eident {id} ->
    begin
      try Hashtbl.find ctx id
      with Not_found ->
        failwith (Printf.sprintf "Variable '%s' not found in context" id)
    end
  (* Functions *)
  | Ecall ({id=func_id}, el) ->
    (* We find the function with id f *)
    begin try
        let (params, body) = Hashtbl.find functions func_id in
        (* We create a new context specific for the function *)
        let new_ctx = Hashtbl.create 17 in
        (* We iterate over the function formal params and assign
         the values provided to the call to each of these vraiables.

         This means we assign the provided values from the el (expr list) 
         to the vars in the function:
         Function f(var1, var2){}
         f(el1, el2)

         *)
        List.iter2 (fun {id} e -> Hashtbl.add new_ctx id (expr ctx e)) params el;
        (* We then try to evaluate the body of the function *)
        (* Retun non if we fail. Else, return value *)
        begin try
                stmt new_ctx body;
                Vnone
            with 
            Return v -> v
        end
    with Not_found ->
      failwith (Printf.sprintf "Function '%s' not found in context" func_id)
    end
  (* Matrix *)
  (* expr list list *)
  | Ematrix l ->
    let matrix = Array.of_list (List.map (fun row ->
      Array.of_list (List.map (expr ctx) row)
    ) l) in
    Vmatrix matrix

(* stmts is all the statements in the block. *)
and stmt ctx = function
  | Sprint e -> print_value (expr ctx e)
  | Sblock stmts -> block ctx stmts
  (* Makes sure that we can call things like functions directly. *)
  | Seval e ->
    ignore (expr ctx e)
  | Sif (e, bl1, bl2) -> 
    if is_true(expr ctx e) 
    then stmt ctx bl1
    (* We check if else block is present *)
    else (match bl2 with
          (* Exectue else if present *)
                | Some b2 -> stmt ctx b2  
          (* Do nothing if not present *)
                | None -> ())
  | Selseif (e, bl1, bl2) ->
    if is_true(expr ctx e) 
    then stmt ctx bl1
    (* We check if else block is present *)
    else (match bl2 with
          (* Exectue else if present *)
                | Some b2 -> stmt ctx b2  
          (* Do nothing if not present *)
                | None -> ())
  | Sassign ({id}, e1, dt) ->
    (* If datatype is set we check it *)
    if(dt <> "") then
    let v1 = expr ctx e1 in
    begin match v1, dt with
    | Vnum v1, "number" -> Hashtbl.replace ctx id (Vnum v1) 
    | Vbool v1, "boolean" -> Hashtbl.replace ctx id (Vbool v1)
    | Vstring v1, "string" -> Hashtbl.replace ctx id (Vstring v1)
    | Varray v1, "array" -> Hashtbl.replace ctx id (Varray v1) 
    (* If we get a array which has the datatype matrix we return matrix *)
    | Varray v1, "matrix" -> Hashtbl.replace ctx id (Vmatrix [|v1|])
    | Vmatrix v1, "matrix" -> Hashtbl.replace ctx id (Vmatrix v1)
    | Vnone, "array" -> Hashtbl.replace ctx id (Varray [||])
    | Vnone, "string" -> Hashtbl.replace ctx id (Vstring "")
    | Vnone, "number" -> Hashtbl.replace ctx id (Vnum 0.0)
    | Vnone, "boolean" -> Hashtbl.replace ctx id (Vbool false)
    | Vnone, "matrix" -> Hashtbl.replace ctx id (Vmatrix [||])
    | _, _ -> failwith (Printf.sprintf "Variable '%s' cannot be initialized" id)
    end
  else 
    (* If datatype is not set we make sure that we only assign to same type *)
    let v1 = expr ctx e1 in
    let v2 = Hashtbl.find ctx id in
    begin match v1, v2 with
      | Vnum v1, Vnum v2 -> Hashtbl.replace ctx id (Vnum v1)
      | Vbool v1, Vbool v2 -> Hashtbl.replace ctx id (Vbool v1)
      | Vstring v1, Vstring v2 -> Hashtbl.replace ctx id (Vstring v1)
      | Varray v1, Varray v2 -> Hashtbl.replace ctx id (Varray v1)
      | Vmatrix v1, Vmatrix v2 -> Hashtbl.replace ctx id (Vmatrix v1)
      | _ , _ -> failwith (Printf.sprintf "%s could not be asssigned to variable '%s' with type %s" (get_datatype v1) id (get_datatype v2) )
    end

  | Sset (e1, e2, e3) ->
    let v1 = expr ctx e1 in
    let v2 = expr ctx e2 in
    let v3 = expr ctx e3 in
    begin match v1, v2 with
      | Varray arr, Vnum index -> 
        if index < 0.0 || index >= float (Array.length arr) then failwith (Printf.sprintf "Index '%d' out of bounds: length is %d " (int_of_float index) (Array.length arr)) 
        else arr.(int_of_float index) <- v3
      | _ -> failwith "Wrong expression types"
    end
  | Ssetmatrix (e1, e2, e3, e4) ->
    let v1 = expr ctx e1 in
    let v2 = expr ctx e2 in
    let v3 = expr ctx e3 in
    let v4 = expr ctx e4 in
    begin match v1, v2, v3 with 
        | Vmatrix matrix, Vnum row, Vnum col -> 
          if row < 0.0 || row >= float (Array.length matrix) || col < 0.0 || col >= float (Array.length matrix.(0)) then
            failwith  (Printf.sprintf "Index [%d, %d] out of bounds: dimensions are %dx%d " (int_of_float row) (int_of_float col) (Array.length matrix) (Array.length matrix.(0)))
          else matrix.(int_of_float row).(int_of_float col) <- v4
        | _ -> failwith "Wrong expression types"
   end
   
  (* For *)
  | Sfor ({id}, e1, e2, s, bl) ->
    let v1 = expr ctx e1 in
    begin match v1 with
    | Vnum v1 ->
        (* Initialize variable in context *)
        Hashtbl.replace ctx id (Vnum v1);
        while
          (* Evaluate the condition *)
          match expr ctx e2 with
          | Vbool cond -> cond
          | _ -> failwith "For-loop condition must evaluate to a boolean"
        do
          (* Execute the block *)
          stmt ctx bl;
          (* Evaluate the stamtent in the end of for *)
          stmt ctx s
        done
    | _ -> failwith "For-loop start value must be a number"
    end
  
  | Srange (e1, e2, bl) ->
    let v1 = expr ctx e1 in
    let v2 = expr ctx e2 in
    begin match v1, v2 with
    | Vnum v1, Vnum v2 ->
      for _ = int_of_float v1 to int_of_float v2 do
        (* Execute the block *)
        stmt ctx bl
      done
    | _ -> failwith "For-loop start and end values must be numbers"
    end
  | Swhile (e, bl) ->
     while 
      (* This is done to evaluate the new value of the condition *)
       match expr ctx e with
        | Vbool cond -> cond
        | _ -> failwith "While-loop condition must evaluate to a boolean"
       do stmt ctx bl done
  (* Return *)
  | Sreturn e ->
      raise (Return (expr ctx e))
  | Sfunc (id, args, bl) ->
    (* Add function to the hashtable *)
    Hashtbl.add functions id.id (args, bl)
and block ctx = function
    | [] -> ()
    | s :: sl -> stmt ctx s; block ctx sl


let file (e) =
    stmt (Hashtbl.create 17) e


