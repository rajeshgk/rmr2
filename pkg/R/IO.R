# Copyright 2011 Revolution Analytics
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


make.json.input.format =
  function(key.class = rmr2:::qw(list, vector, data.frame, matrix),
           value.class = rmr2:::qw(list, vector, data.frame, matrix), #leave the pkg qualifier in here
           nrows = 10^4) {
    key.class = match.arg(key.class)
    value.class = match.arg(value.class)
    cast =
      function(class)
        switch(
          class,
          list = identity,
          vector = as.vector,
          data.frame = function(x) do.call(data.frame, x),
          matrix = function(x) do.call(rbind, x))
    process.field =
      function(field, class)
        cast(class)(fromJSON(field, asText = TRUE))
    function(con) {
      lines = readLines(con, nrows)
      if (length(lines) == 0) NULL
      else {
        splits =  strsplit(lines, "\t")
        c.keyval(
          lapply(splits,
                 function(x)
                   if(length(x) == 1)
                     keyval(NULL, process.field(x[1], value.class))
                 else
                   keyval(process.field(x[1], key.class), process.field(x[2], value.class))))}}}



make.json.output.format =
  function(write.size = 10^4)
    function(kv, con) {
      ser =
        function(k, v)
          paste(
            gsub(
              "\n",
              "",
              toJSON(k, .escapeEscapes=TRUE, collapse = "")),
            gsub("\n", "", toJSON(v, .escapeEscapes=TRUE, collapse = "")),
            sep = "\t")
      out = reduce.keyval(kv, ser, write.size)
      writeLines(paste(out, collapse = "\n"), sep = "\n", con = con)}

make.text.input.format =
  function(nrows = 10^4)
    function(con) {
      lines = readLines(con, nrows)
      if (length(lines) == 0) NULL
      else keyval(NULL, lines)}

text.output.format =
  function(kv, con) {
    ser = function(k, v) paste(k, v, collapse = "", sep = "\t")
    out = reduce.keyval(kv, ser, length.keyval(kv))
    writeLines(as.character(out), con = con)}

make.csv.input.format =
  function(..., nrows = 10^4) {
    args = list(...)
    function(con) {
      df =
        tryCatch(
          do.call(read.table, c(list(file = con, header = FALSE, nrows = nrows), args)),
          error =
            function(e) {
              if(e$message != "no lines available in input")
                stop(e$message)
              NULL})
      if(is.null(df) || dim(df)[[1]] == 0) NULL
      else keyval(NULL, df)}}

make.csv.output.format =
  function(...) function(kv, con) {
    k = keys(kv)
    v = values(kv)
    write.table(file = con,
                x = if(is.null(k)) v else cbind(k, v),
                ...,
                row.names = FALSE,
                col.names = FALSE)}

typedbytes.reader =
  function(data) {
    if(is.null(data)) NULL
    else
      .Call("typedbytes_reader", data, PACKAGE = "rmr2")}

make.typedbytes.input.format = function(recycle = TRUE) {
  obj.buffer = list()
  obj.buffer.rmr.length = 0
  raw.buffer = raw()
  read.size = 100
  function(con, keyval.length) {
    while(length(obj.buffer) < 2 ||
            obj.buffer.rmr.length < keyval.length) {
      raw.buffer <<- c(raw.buffer, readBin(con, raw(), read.size))
      if(length(raw.buffer) == 0) break;
      parsed = typedbytes.reader(raw.buffer, as.integer(read.size/2))
      obj.buffer <<- c(obj.buffer, parsed$objects)
      approx.read.records = {
        if(length(parsed$objects) == 0) 0
        else
          sum(
            sapply(sample(parsed$objects, 10, replace = T), rmr.length)) *
          length(parsed$objects)/10.0 }
      obj.buffer.rmr.length <<- obj.buffer.rmr.length + approx.read.records
      read.size <<- ceiling(1.1^sign(keyval.length - obj.buffer.rmr.length) * read.size)
      if(parsed$length != 0) raw.buffer <<- raw.buffer[-(1:parsed$length)]}
    straddler = list()
    retval =
      if(length(obj.buffer) == 0) NULL
    else {
      if(length(obj.buffer)%%2 ==1) {
        straddler = obj.buffer[length(obj.buffer)]
        obj.buffer <<- obj.buffer[-length(obj.buffer)]}
      kk = odd(obj.buffer)
      vv = even(obj.buffer)
      if(recycle) {
        keyval(
          c.or.rbind.rep(kk, sapply.rmr.length(vv)),
          c.or.rbind(vv))}
      else {
        keyval(kk, vv)}}
    obj.buffer <<- straddler
    obj.buffer.rmr.length <<- 0
    retval}}

make.native.input.format = make.typedbytes.input.format

typedbytes.writer =
  function(objects, con, native) {
    writeBin(
      .Call("typedbytes_writer", objects, native, PACKAGE = "rmr2"),
      con)}

setAs("integer", "Date", function(from) as.Date(from, origin = "1970-1-1"))

rmr.coerce =
  function(x, template) {
    if(is.atomic(template))
      switch(
        class(template),
        factor = factor(unlist(x)),
        as(unlist(x), class(template)))
    else
      I(splat(c)(x))}

to.data.frame =
  function(x, template){
    x = t.list(x)
    y =
      lapply(
        seq_along(template),
        function(i)
          rmr.coerce(x[[i]], template[[i]]))
    names(y) = names(template)
    df = data.frame(y, stringsAsFactors = FALSE)
    candidate.names = make.unique(rmr.coerce(x[[length(x)]], character()))
    rownames(df) =  make.unique(ifelse(is.na(candidate.names), "NA", candidate.names))
    df}

from.list =
  function (x, template) {
    switch(
      class(template),
      NULL = NULL,
      list = splat(c)(x),
      matrix = splat(rbind)(x),
      data.frame = to.data.frame(x, template),
      factor = factor(unlist(x)),
      unlist(x))}

make.typedbytes.input.format =
  function(read.size = 10^7, native = FALSE) {
    obj.buffer = list()
    obj.buffer.rmr.length = 0
    raw.buffer = raw()
    template = NULL
    function(con) {
      while(length(obj.buffer) < 2 || (native && is.null(template))) {
        raw.buffer <<- c(raw.buffer, readBin(con, raw(), read.size))
        if(length(raw.buffer) == 0) break;
        parsed = typedbytes.reader(raw.buffer)
        if(is.null(template) && !is.null(parsed$template))
          template <<- parsed$template
        if(parsed$starting.template)
          obj.buffer <<- obj.buffer[-length(obj.buffer)]
        obj.buffer <<- c(obj.buffer, parsed$objects)
        if(parsed$length != 0) raw.buffer <<- raw.buffer[-(1:parsed$length)]}
      straddler = list()
      retval = {
        if(length(obj.buffer) == 0) NULL
        else {
          if(length(obj.buffer)%%2 ==1) {
            straddler = obj.buffer[length(obj.buffer)]
            obj.buffer <<- obj.buffer[-length(obj.buffer)]}
          kk = odd(obj.buffer)
          vv = even(obj.buffer)
          if(native) {
            stopifnot(!is.null(template))
            kk = rep(
              kk,
              if(is.data.frame(template[[2]]))
                sapply.rmr.length.lossy.data.frame(vv)
              else
                sapply.rmr.length(vv))
            keyval(
              from.list(kk, template[[1]]),
              from.list(vv, template[[2]]))}
          else
            keyval(kk, vv)}}
      obj.buffer <<- straddler
      retval}}

make.native.input.format = Curry(make.typedbytes.input.format, native = TRUE)

to.list =
  function(x) {
    if (is.null(x))
      list(NULL)
    else {
      if (is.matrix(x)) x = as.data.frame(x)
      if (is.data.frame(x))
        unname(
          t.list(
            lapply(
              x,
              function(x) if(is.factor(x)) as.character(x) else x)))
      else
        as.list(if(is.factor(x)) as.character(x) else x)}}

intersperse =
  function(a.list, another.list, every.so.many)
    c(
      another.list[1],
      splat(c)(
        mapply(
          split(a.list, ceiling(seq_along(a.list)/every.so.many), drop = TRUE),
          lapply(another.list, list),
          FUN = c,
          SIMPLIFY = FALSE)))

intersperse.one =
  function(a.list, an.element, every.so.many)
    c(
      splat(c)(
        lapply(
          split(a.list, ceiling(seq_along(a.list)/every.so.many)),
          function(y) c(list(an.element), y))),
      list(an.element))

delevel =
  function(x) {
    if(is.factor(x)) factor(x)
    else{
      if(is.data.frame(x))
        structure(
          data.frame(lapply(x, delevel), stringsAsFactors = FALSE),
          row.names = row.names(x))
      else x}}

make.native.or.typedbytes.output.format =
  function(native, write.size = 10^6) {
    template = NULL
    function(kv, con){
      if(length.keyval(kv) != 0) {
        k = keys(kv)
        v = values(kv)
        kvs = {
          if(native)
            split.keyval(kv, write.size, TRUE)
          else
            keyval(to.list(k), to.list(v))}
        if(is.null(k)) {
          if(!native) stop("Can't handle NULL in typedbytes")
          ks =  rep(list(NULL), length.keyval(kvs)) }
        else
          ks = keys(kvs)
        vs = values(kvs)
        if(native) {
          if(is.null(template))  {
            template <<-
              list(
                key = delevel(rmr.slice(k, 0)),
                val = delevel(rmr.slice(v, 0)))}
          N = {
            if(length(vs) < 100) 1
            else {
              r = ceiling((object.size(ks) + object.size(vs))/10^6)
              if (r < 100) length(vs) / 100
              else r}}
          ks = intersperse(ks, sample(ks, ceiling(length(ks)/N)), N)
          vs = intersperse.one(vs, structure(template, rmr.template = TRUE), N)}
        typedbytes.writer(
          interleave(ks, vs),
          con,
          native)}}}

make.native.output.format =
  Curry(make.native.or.typedbytes.output.format, native = TRUE)
make.typedbytes.output.format =
  Curry(make.native.or.typedbytes.output.format, native = FALSE)

pRawToChar =
  function(rl)
    .Call("raw_list_to_character", rl, PACKAGE="rmr2")

hbase.rec.to.data.frame =
  function(
    source,
    atomic,
    dense,
    key.deserialize = pRawToChar,
    cell.deserialize =
      function(x, column, family) pRawToChar(x)) {
    filler = replicate(length(unlist(source))/2, NULL)
    dest =
      list(
        key = filler,
        family = filler,
        column = filler,
        cell = filler)
    tmp =
      .Call(
        "hbase_to_df",
        source,
        dest,
        PACKAGE="rmr2")
    retval = data.frame(
      key =
        I(
          key.deserialize(
            tmp$data.frame$key[1:tmp$nrows])),
      family =
        pRawToChar(
          tmp$data.frame$family[1:tmp$nrows]),
      column =
        pRawToChar(
          tmp$data.frame$column[1:tmp$nrows]),
      cell =
        I(
          cell.deserialize(
            tmp$data.frame$cell[1:tmp$nrows],
            tmp$data.frame$family[1:tmp$nrows],
            tmp$data.frame$column[1:tmp$nrows])))
    if(atomic)
      retval =
      as.data.frame(
        lapply(
          retval,
          function(x) if(is.factor(x)) x else unclass(x)))
    if(dense) retval = dcast(retval, key ~ family + column)
    retval}

make.hbase.input.format =
  function(dense, atomic, key.deserialize, cell.deserialize, read.size) {
    deserialize.opt =
      function(deser) {
        if(is.null(deser)) deser = "raw"
        if(is.character(deser))
          deser =
          switch(
            deser,
            native =
              function(x, family = NULL, column = NULL) lapply(x, unserialize),
            typedbytes =
              function(x, family = NULL, column = NULL)
                typedbytes.reader(
                  do.call(c, x)),
            raw = function(x, family = NULL, column = NULL) pRawToChar(x))
        deser}
    key.deserialize = deserialize.opt(key.deserialize)
    cell.deserialize = deserialize.opt(cell.deserialize)
    tif = make.typedbytes.input.format(read.size)
    if(is.null(dense)) dense = FALSE
    function(con) {
      rec = tif(con)
      if(is.null(rec)) NULL
      else {
        df = hbase.rec.to.data.frame(rec, atomic, dense, key.deserialize, cell.deserialize)
        keyval(NULL, df)}}}

data.frame.to.nested.map =
  function(x, ind) {
    if(length(ind)>0 && nrow(x) > 0) {
      spl = split(x, x[, ind[1]])
      lapply(x[, ind[1]], function(y) keyval(as.character(y), data.frame.to.nested.map(spl[[y]], ind[-1])))}
    else x$value}

hbdf.to.m3 = Curry(data.frame.to.nested.map, ind = c("key", "family", "column"))
# I/O

open.stdinout =
  function(mode, is.read) {
    if(mode == "text") {
      if(is.read)
        file("stdin", "r") #not stdin() which is parsed by the interpreter
      else
        stdout()}
    else { # binary
      cat  = {
        if(.Platform$OS.type == "windows")
          paste(
            "\"",
            system.file(
              package="rmr2",
              "bin",
              .Platform$r_arch,
              "catwin.exe"),
            "\"",
            sep="")
        else
          "cat"}
      pipe(cat, ifelse(is.read, "rb", "wb"))}}


make.keyval.readwriter =
  function(fname, format, is.read) {
    con = {
      if(is.null(fname))
        open.stdinout(format$mode, is.read)
      else
        file(
          fname,
          paste(
            if(is.read) "r" else "w",
            if(format$mode == "text") "" else "b",
            sep = ""))}
    if (is.read) {
      function()
        format$format(con)}
    else {
      function(kv)
        format$format(kv, con)}}

make.keyval.reader = Curry(make.keyval.readwriter, is.read = TRUE)
make.keyval.writer = Curry(make.keyval.readwriter, is.read = FALSE)

paste.fromJSON =
  function(...)
    tryCatch(
      rjson::fromJSON(paste("[", paste(..., sep = ", "), "]")),
      error =
        function(e){
          if(is.element(e$message, paste0("unexpected character", c(" 'N'", " 'I'", ": I"), "\n")))
            e$message = ("Found unexpected character, try updating Avro to 1.7.7 or trunk")
          stop(e$message)})

make.avro.input.format.function =
  function(schema.file, ..., read.size = 10^5) {
    if(!require("ravro"))
      stop("Package ravro needs to be installed before using this format")
    schema = ravro:::avro_get_schema(file = schema.file)
    function(con) {
      lines =
        readLines(con = con, n = read.size)
      if  (length(lines) == 0) NULL
      else {
        x = splat(paste.fromJSON)(lines)
        y = ravro:::parse_avro(x, schema, encoded_unions=FALSE, ...)
        keyval(NULL, y)}}}

IO.formats = c("text", "json", "csv", "native",
               "sequence.typedbytes", "hbase",
               "pig.hive", "avro")

make.input.format =
  function(
    format = "native",
    mode = c("binary", "text"),
    streaming.format = NULL,
    backend.parameters = NULL,
    ...) {
    mode = match.arg(mode)
    backend.parameters = NULL
    optlist = list(...)
    if(is.character(format)) {
      format = match.arg(format, IO.formats)
      switch(
        format,
        text = {
          format = make.text.input.format(...)
          mode = "text"},
        json = {
          format = make.json.input.format(...)
          mode = "text"},
        csv = {
          format = make.csv.input.format(...)
          mode = "text"},
        native = {
          format = make.native.input.format(...)
          mode = "binary"},
        sequence.typedbytes = {
          format = make.typedbytes.input.format(...)
          mode = "binary"},
        pig.hive = {
          format =
            make.csv.input.format(
              sep = "\001",
              comment.char = "",
              fill = TRUE,
              flush = TRUE,
              quote = "")
          mode = "text"},
        hbase = {
          format =
            make.hbase.input.format(
              default(args$dense, FALSE),
              default(args$atomic, FALSE),
              default(args$key.deserialize, "raw"),
              default(args$cell.deserialize, "raw"),
              default(args$read.size, 10^6))
          mode = "binary"
          streaming.format =
            "com.dappervision.hbase.mapred.TypedBytesTableInputFormat"
          family.columns = args$family.columns
          start.row = args$start.row
          stop.row = args$stop.row
          regex.row.filter=args$regex.row.filter
          backend.parameters =
            list(
              hadoop =
                c(
                  list(
                    D =
                      paste(
                        "hbase.mapred.tablecolumnsb64=",
                        paste(
                          sapply(
                            names(family.columns),
                            function(fam)
                              paste(
                                sapply(
                                  1:length(family.columns[[fam]]),
                                  function(i)
                                    base64encode(
                                      paste(
                                        fam,
                                        ":",
                                        family.columns[[fam]][i],
                                        sep = "",
                                        collapse = ""))),
                                sep = "",
                                collapse = " ")),
                          collapse = " "),
                        sep = "")),
                  if(!is.null(start.row))
                    list(
                      D =
                        paste(
                          "hbase.mapred.startrowb64=",
                          base64encode(start.row),
                          sep = "")),
                  if(!is.null(stop.row))
                    list(
                      D =
                        paste(
                          "hbase.mapred.stoprowb64=",
                          base64encode(stop.row),
                          sep = "")),
                  if(!is.null(regex.row.filter))
                    list(
                      D =
                        paste(
                          "hbase.mapred.rowfilter=",
                          regex.row.filter,
                          sep = "")),
                  list(
                    libjars = system.file(package = "rmr2", "hadoopy_hbase.jar"))))},
        avro = {
          format = make.avro.input.format.function(...)
          mode = "text"
          streaming.format = "org.apache.avro.mapred.AvroAsTextInputFormat"
          backend.parameters =
            list(
              hadoop =
                list(
                  libjars =
                    gsub(
                      if(.Platform$OS.type == "windows") 
                        ";"
                      else
                        ":",
                      ", ", Sys.getenv("AVRO_LIBS"))))})}
    if(is.null(streaming.format) && mode == "binary")
      streaming.format = "org.apache.hadoop.streaming.AutoInputFormat"
    list(mode = mode,
         format = format,
         streaming.format = streaming.format,
         backend.parameters = backend.parameters)}

set.separator.options =
  function(sep) {
    if(!is.null(sep))
      list(
        hadoop =
          list(
            D =
              paste(
                "mapred.textoutputformat.separator=",
                sep,
                sep = ""),
            D =
              paste(
                "stream.map.output.field.separator=",
                sep,
                sep = ""),
            D =
              paste(
                "stream.reduce.output.field.separator=",
                sep,
                sep = "")))}

make.output.format =
  function(
    format = "native",
    mode = c("binary", "text"),
    streaming.format = NULL,
    backend.parameters = NULL,
    ...) {
    mode = match.arg(mode)
    args = list(...)
    if(is.character(format)) {
      format = match.arg(format, IO.formats)
      switch(
        format,
        text = {
          format = text.output.format
          mode = "text"
          streaming.format = NULL},
        json = {
          format = make.json.output.format(...)
          mode = "text"
          streaming.format = NULL},
        csv = {
          format = make.csv.output.format(...)
          mode = "text"
          streaming.format = NULL
          backend.parameters = set.separator.options(args$sep)},
        pig.hive = {
          format =
            make.csv.output.format(
              sep = "\001",
              quote = FALSE)
          mode = "text"
          streaming.format = NULL},
        native = {
          format = make.native.output.format(...)
          mode = "binary"
          streaming.format = "org.apache.hadoop.mapred.SequenceFileOutputFormat"},
        sequence.typedbytes = {
          format = make.typedbytes.output.format(...)
          mode = "binary"
          streaming.format = "org.apache.hadoop.mapred.SequenceFileOutputFormat"},
        hbase = {
          stop("hbase output format not implemented yet")
          format = make.typedbytes.output.format(...)
          mode = "binary"
          streaming.format = "com.dappervision.mapreduce.TypedBytesTableOutputFormat"
          backend.parameters =
            list(
              hadoop =
                list(
                  D = paste(
                    "hbase.mapred.tablecolumnsb64=",
                    args$family,
                    ":",
                    args$column,
                    sep = ""),
                  libjars = system.file(package = "rmr2", "java/hadoopy_hbase.jar")))})}
    mode = match.arg(mode)
    list(
      mode = mode,
      format = format,
      streaming.format = streaming.format,
      backend.parameters = backend.parameters)}
