
module Ht = Hashtbl

type filename = string

let string_of_key (k: 'a): string =
  Marshal.(to_string k [No_sharing])

let string_of_value (v: 'b): string =
  Marshal.(to_string v [No_sharing])

let key_of_string (k_str: string): 'a =
  (Marshal.from_string k_str 0: 'a)

let value_of_string (v_str: string): 'b =
  (Marshal.from_string v_str 0: 'b)

type position = { off: int;
                  len: int }

type open_mode = Read_only
               | Read_write

type db = { data_fn: filename;
            index_fn: filename;
            data: Unix.file_descr;
            index: (string, position) Hashtbl.t;
            mode: open_mode }

module StrKeyToStrVal = struct

  type t = db

  let create fn =
    let data_fn = fn in
    let index_fn = fn ^ ".idx" in
    let data =
      Unix.(openfile data_fn [O_RDWR; O_CREAT; O_EXCL] 0o600) in
    (* we just check there is not already an index file *)
    let index_file =
      Unix.(openfile index_fn [O_RDWR; O_CREAT; O_EXCL] 0o600) in
    Unix.close index_file;
    let index = Ht.create 11 in
    let mode = Read_write in
    { data_fn; index_fn; data; index; mode }

  let open_rw fn =
    let data_fn = fn in
    let index_fn = fn ^ ".idx" in
    let data =
      Unix.(openfile data_fn [O_RDWR] 0o600) in
    let index = Utls.restore index_fn in
    let mode = Read_write in
    { data_fn; index_fn; data; index; mode }

  let open_ro fn =
    let data_fn = fn in
    let index_fn = fn ^ ".idx" in
    let data =
      Unix.(openfile data_fn [O_RDONLY] 0o600) in
    let index = Utls.restore index_fn in
    let mode = Read_only in
    { data_fn; index_fn; data; index; mode }

  let close db =
    Unix.close db.data;
    if db.mode = Read_write then
      Utls.save db.index_fn db.index

  let sync db =
    if db.mode = Read_write then
      begin
        ExtUnix.All.fsync db.data;
        Utls.save db.index_fn db.index
      end

  let destroy db =
    if db.mode = Read_write then
      begin
        close db;
        Sys.remove db.data_fn;
        Sys.remove db.index_fn
      end

  let mem db k =
    Ht.mem db.index k

  let add db k str =
    (* go to end of data file *)
    let off = Unix.(lseek db.data 0 SEEK_END) in
    let len = String.length str in
    let written = Unix.write_substring db.data str 0 len in
    assert(written = len);
    Ht.add db.index k { off; len }

  let replace db k str =
    (* go to end of data file *)
    let off = Unix.(lseek db.data 0 SEEK_END) in
    let len = String.length str in
    let written = Unix.write_substring db.data str 0 len in
    assert(written = len);
    Ht.replace db.index k { off; len }

  let remove db k =
    (* we just remove it from the index, not from the data file *)
    Ht.remove db.index k

  let retrieve db v_addr =
    let off = v_addr.off in
    let len = v_addr.len in
    let buff = Bytes.create len in
    let off' = Unix.(lseek db.data off SEEK_SET) in
    assert(off' = off);
    let read = Unix.read db.data buff 0 len in
    assert(read = len);
    Bytes.unsafe_to_string buff

  let find db k =
    let v_addr = Ht.find db.index k in
    retrieve db v_addr

  let iter f db =
    Ht.iter (fun k v ->
        f k (retrieve db v)
      ) db.index

  let fold f db init =
    Ht.fold (fun k v acc ->
        f k (retrieve db v) acc
      ) db.index init

end
