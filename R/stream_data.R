stream_read_generic_type <- function(sc,
                                     path,
                                     type,
                                     name,
                                     columns = NULL,
                                     stream_options = list())
{
  switch(type,
    csv = {
      spark_csv_read(
        sc,
        spark_normalize_path(path),
        stream_options,
        columns)
    },
    {
      spark_session(sc) %>%
        invoke("read") %>%
        invoke(type, path)
    }
  )
}

stream_read_generic <- function(sc,
                                path,
                                type,
                                name,
                                columns,
                                stream_options)
{
  spark_require_version(sc, "2.0.0", "Spark streaming")

  schema <- NULL

  streamOptions <- spark_session(sc) %>%
    invoke("readStream")

  if (identical(columns, NULL)) {
    reader <- stream_read_generic_type(sc,
                                       path,
                                       type,
                                       name,
                                       columns = columns,
                                       stream_options = stream_options)
    schema <- invoke(reader, "schema")
  }
  else if ("spark_jobj" %in% class(columns)) {
    schema <- columns
  }
  else {
    schema <- spark_data_build_types(sc, columns)
  }

  for (optionName in names(stream_options)) {
    streamOptions <- invoke(streamOptions, "option", optionName, stream_options[[optionName]])
  }

  streamOptions %>%
    invoke("schema", schema) %>%
    invoke(type, path) %>%
    invoke("createOrReplaceTempView", name)

  tbl(sc, name)
}

stream_write_generic <- function(x, path, type, mode, trigger, checkpoint, stream_options)
{
  spark_require_version(spark_connection(x), "2.0.0", "Spark streaming")

  sdf <- spark_dataframe(x)
  sc <- spark_connection(x)
  mode <- match.arg(as.character(mode), choices = c("append", "complete", "update"))

  if (!sdf_is_streaming(sdf))
    stop("DataFrame requires streaming context. Use `stream_read_*()` to read from streams.")

  streamOptions <- invoke(sdf, "writeStream") %>%
    invoke("format", type)

  stream_options$path <- path

  stream_options$checkpointLocation <- checkpoint

  for (optionName in names(stream_options)) {
    streamOptions <- invoke(streamOptions, "option", optionName, stream_options[[optionName]])
  }

  trigger <- stream_trigger_create(trigger, sc)

  if (identical(type, "memory")) streamOptions <- invoke(streamOptions, "queryName", path)

  streamOptions %>%
    invoke("outputMode", mode) %>%
    invoke("trigger", trigger) %>%
    invoke("start") %>%
    stream_class() %>%
    stream_validate()
}

#' Read CSV Stream
#'
#' Reads a CSV stream as a Spark dataframe stream.
#'
#' @inheritParams spark_read_csv
#' @param name The name to assign to the newly generated stream.
#'
#' @family Spark stream serialization
#'
#' @export
stream_read_csv <- function(sc,
                            path,
                            name = NULL,
                            header = TRUE,
                            columns = NULL,
                            delimiter = ",",
                            quote = "\"",
                            escape = "\\",
                            charset = "UTF-8",
                            null_value = NULL,
                            options = list(),
                            ...)
{
  spark_require_version(sc, "2.0.0", "Spark streaming")

  name <- name %||% random_string("sparklyr_tmp_")

  infer_schema <- identical(columns, NULL) || is.character(columns)

  streamOptions <- spark_csv_options(header = header,
                                     inferSchema = infer_schema,
                                     delimiter = delimiter,
                                     quote = quote,
                                     escape = escape,
                                     charset = charset,
                                     nullValue = null_value,
                                     options = options)

  stream_read_generic(sc,
                      path = path,
                      type = "csv",
                      name = name,
                      columns = columns,
                      stream_options = streamOptions)
}

#' Write CSV Stream
#'
#' Writes a Spark dataframe stream into a tabular (typically, comma-separated) stream.
#'
#' @inheritParams spark_write_csv
#'
#' @param mode Specifies how data is written to a streaming sink. Valid values are
#'   \code{"append"}, \code{"complete"} or \code{"update"}.
#' @param trigger The trigger for the stream query, defaults to micro-batches runnnig
#'   every 5 seconds. See \code{\link{stream_trigger_interval}} and
#'   \code{\link{stream_trigger_continuous}}.
#' @param checkpoint The location where the system will write all the checkpoint.
#' information to guarantee end-to-end fault-tolerance.
#'
#' @family Spark stream serialization
#'
#' @export
stream_write_csv <- function(x,
                             path,
                             mode = c("append", "complete", "update"),
                             trigger = stream_trigger_interval(interval = 5000),
                             checkpoint = file.path(path, "checkpoint"),
                             header = TRUE,
                             delimiter = ",",
                             quote = "\"",
                             escape = "\\",
                             charset = "UTF-8",
                             null_value = NULL,
                             options = list(),
                             ...)
{
  spark_require_version(spark_connection(x), "2.0.0", "Spark streaming")

  streamOptions <- spark_csv_options(header = header,
                                     inferSchema = NULL,
                                     delimiter = delimiter,
                                     quote = quote,
                                     escape = escape,
                                     charset = charset,
                                     nullValue = null_value,
                                     options = options)

  stream_write_generic(x,
                       path = path,
                       type = "csv",
                       mode = mode,
                       trigger = trigger,
                       checkpoint = checkpoint,
                       stream_options = streamOptions)
}

#' Write Memory Stream
#'
#' Writes a Spark dataframe stream into a memory stream.
#'
#' @inheritParams stream_write_csv
#'
#' @param name The name to assign to the newly generated stream.
#'
#' @family Spark stream serialization
#'
#' @examples
#' \dontrun{
#'
#' sc <- spark_connect(master = "local")
#'
#' dir.create("iris-in")
#' write.csv(iris, "iris-in/iris.csv", row.names = FALSE)
#'
#' stream <- stream_read_csv(sc, "iris-in") %>% stream_write_memory()
#'
#' stop_stream(stream)
#'
#' }
#'
#' @export
stream_write_memory <- function(x,
                                name = random_string("sparklyr_tmp_"),
                                mode = c("append", "complete", "update"),
                                trigger = stream_trigger_interval(interval = 5000),
                                checkpoint = file.path("checkpoints", name, random_string("")),
                                options = list(),
                                ...)
{
  spark_require_version(spark_connection(x), "2.0.0", "Spark streaming")

  sc <- spark_connection(x)

  stream_write_generic(x,
                       path = name,
                       type = "memory",
                       mode = mode,
                       trigger = trigger,
                       checkpoint = checkpoint,
                       stream_options = options)
}

#' Read Text Stream
#'
#' Reads a text stream as a Spark dataframe stream.
#'
#' @inheritParams stream_read_csv
#'
#' @family Spark stream serialization
#'
#' @export
stream_read_text <- function(sc,
                             path,
                             name = NULL,
                             options = list(),
                             ...)
{
  spark_require_version(sc, "2.0.0", "Spark streaming")

  name <- name %||% random_string("sparklyr_tmp_")

  stream_read_generic(sc,
                      path = path,
                      type = "text",
                      name = name,
                      columns = list(text = "character"),
                      stream_options = options)
}

#' Write Text Stream
#'
#' Writes a Spark dataframe stream into a text stream.
#'
#' @inheritParams stream_write_memory
#'
#' @family Spark stream serialization
#'
#' @examples
#' \dontrun{
#'
#' sc <- spark_connect(master = "local")
#'
#' dir.create("text-in")
#' write.csv("A text entry", "text-in/text.txt", row.names = FALSE)
#'
#' stream <- stream_read_text(sc, "text-in") %>% stream_write_text("text-out")
#'
#' stop_stream(stream)
#'
#' }
#'
#' @export
stream_write_text <- function(x,
                              name = random_string("sparklyr_tmp_"),
                              mode = c("append", "complete", "update"),
                              trigger = stream_trigger_interval(interval = 5000),
                              checkpoint = file.path("checkpoints", name, random_string("")),
                              options = list(),
                              ...)
{
  spark_require_version(spark_connection(x), "2.0.0", "Spark streaming")

  sc <- spark_connection(x)

  stream_write_generic(x,
                       path = name,
                       type = "text",
                       mode = mode,
                       trigger = trigger,
                       checkpoint = checkpoint,
                       stream_options = options)
}

#' Read JSON Stream
#'
#' Reads a JSON stream as a Spark dataframe stream.
#'
#' @inheritParams stream_read_csv
#'
#' @family Spark stream serialization
#'
#' @export
stream_read_json <- function(sc,
                             path,
                             name = NULL,
                             columns = NULL,
                             options = list(),
                             ...)
{
  spark_require_version(sc, "2.0.0", "Spark streaming")

  name <- name %||% random_string("sparklyr_tmp_")

  stream_read_generic(sc,
                      path = path,
                      type = "json",
                      name = name,
                      columns = columns,
                      stream_options = options)
}

#' Write JSON Stream
#'
#' Writes a Spark dataframe stream into a JSON stream.
#'
#' @inheritParams stream_write_memory
#'
#' @family Spark stream serialization
#'
#' @examples
#' \dontrun{
#'
#' sc <- spark_connect(master = "local")
#'
#' dir.create("json-in")
#' jsonlite::write_json(list(a = c(1,2), b = c(10,20)), "../streaming/json-in/data.json")
#'
#' stream <- stream_read_json(sc, "json-in") %>% stream_write_json("json-out")
#'
#' stop_stream(stream)
#'
#' }
#'
#' @export
stream_write_json <- function(x,
                              name = random_string("sparklyr_tmp_"),
                              mode = c("append", "complete", "update"),
                              trigger = stream_trigger_interval(interval = 5000),
                              checkpoint = file.path("checkpoints", name, random_string("")),
                              options = list(),
                              ...)
{
  spark_require_version(spark_connection(x), "2.0.0", "Spark streaming")

  sc <- spark_connection(x)

  stream_write_generic(x,
                       path = name,
                       type = "json",
                       mode = mode,
                       trigger = trigger,
                       checkpoint = checkpoint,
                       stream_options = options)
}

#' Read Parquet Stream
#'
#' Reads a parquet stream as a Spark dataframe stream.
#'
#' @inheritParams stream_read_csv
#'
#' @family Spark stream serialization
#'
#' @export
stream_read_parquet <- function(sc,
                                path,
                                name = NULL,
                                columns = NULL,
                                options = list(),
                                ...)
{
  spark_require_version(sc, "2.0.0", "Spark streaming")

  name <- name %||% random_string("sparklyr_tmp_")

  stream_read_generic(sc,
                      path = path,
                      type = "parquet",
                      name = name,
                      columns = columns,
                      stream_options = options)
}

#' Write Parquet Stream
#'
#' Writes a Spark dataframe stream into a parquet stream.
#'
#' @inheritParams stream_write_memory
#'
#' @family Spark stream serialization
#'
#' @examples
#' \dontrun{
#'
#' sc <- spark_connect(master = "local")
#'
#' sdf_len(sc, 10) %>% spark_write_parquet("parquet-in")
#'
#' stream <- stream_read_parquet(sc, "parquet-in") %>% stream_write_parquet("parquet-out")
#'
#' stop_stream(stream)
#'
#' }
#'
#' @export
stream_write_parquet <- function(x,
                                 name = random_string("sparklyr_tmp_"),
                                 mode = c("append", "complete", "update"),
                                 trigger = stream_trigger_interval(interval = 5000),
                                 checkpoint = file.path("checkpoints", name, random_string("")),
                                 options = list(),
                                 ...)
{
  spark_require_version(spark_connection(x), "2.0.0", "Spark streaming")

  sc <- spark_connection(x)

  stream_write_generic(x,
                       path = name,
                       type = "parquet",
                       mode = mode,
                       trigger = trigger,
                       checkpoint = checkpoint,
                       stream_options = options)
}

#' Read ORC Stream
#'
#' Reads an \href{https://orc.apache.org/}{ORC} stream as a Spark dataframe stream.
#'
#' @inheritParams stream_read_csv
#'
#' @family Spark stream serialization
#'
#' @export
stream_read_orc <- function(sc,
                            path,
                            name = NULL,
                            columns = NULL,
                            options = list(),
                            ...)
{
  spark_require_version(sc, "2.0.0", "Spark streaming")

  name <- name %||% random_string("sparklyr_tmp_")

  stream_read_generic(sc,
                      path = path,
                      type = "orc",
                      name = name,
                      columns = columns,
                      stream_options = options)
}

#' Write a ORC Stream
#'
#' Writes a Spark dataframe stream into an \href{https://orc.apache.org/}{ORC} stream.
#'
#' @inheritParams stream_write_memory
#'
#' @family Spark stream serialization
#'
#' @examples
#' \dontrun{
#'
#' sc <- spark_connect(master = "local")
#'
#' sdf_len(sc, 10) %>% spark_write_orc("orc-in")
#'
#' stream <- stream_read_parquet(sc, "orc-in") %>% stream_write_parquet("orc-out")
#'
#' stop_stream(stream)
#'
#' }
#'
#' @export
stream_write_orc <- function(x,
                             name = random_string("sparklyr_tmp_"),
                             mode = c("append", "complete", "update"),
                             trigger = stream_trigger_interval(interval = 5000),
                             checkpoint = file.path("checkpoints", name, random_string("")),
                             options = list(),
                             ...)
{
  spark_require_version(spark_connection(x), "2.0.0", "Spark streaming")

  sc <- spark_connection(x)

  stream_write_generic(x,
                       path = name,
                       type = "orc",
                       mode = mode,
                       trigger = trigger,
                       checkpoint = checkpoint,
                       stream_options = options)
}

#' Read Kafka Stream
#'
#' Reads a Kafka stream as a Spark dataframe stream.
#'
#' @inheritParams stream_read_csv
#'
#' @family Spark stream serialization
#'
#' @export
stream_read_kafka <- function(sc,
                              path,
                              name = NULL,
                              columns = NULL,
                              options = list(),
                              ...)
{
  spark_require_version(sc, "2.0.0", "Spark streaming")

  name <- name %||% random_string("sparklyr_tmp_")

  stream_read_generic(sc,
                      path = path,
                      type = "kafka",
                      name = name,
                      columns = columns,
                      stream_options = options)
}

#' Write Kafka Stream
#'
#' Writes a Spark dataframe stream into an kafka stream.
#'
#' @inheritParams stream_write_memory
#'
#' @family Spark stream serialization
#'
#' @examples
#' \dontrun{
#'
#' sc <- spark_connect(master = "local")
#'
#' sdf_len(sc, 10) %>% spark_write_orc("orc-in")
#'
#' stream <- stream_read_parquet(sc, "orc-in") %>% stream_write_parquet("orc-out")
#'
#' stop_stream(stream)
#'
#' }
#'
#' @export
stream_write_kafka <- function(x,
                               name = random_string("sparklyr_tmp_"),
                               mode = c("append", "complete", "update"),
                               trigger = stream_trigger_interval(interval = 5000),
                               checkpoint = file.path("checkpoints", name, random_string("")),
                               options = list(),
                               ...)
{
  spark_require_version(spark_connection(x), "2.0.0", "Spark streaming")

  sc <- spark_connection(x)

  stream_write_generic(x,
                       path = name,
                       type = "kafka",
                       mode = mode,
                       trigger = trigger,
                       checkpoint = checkpoint,
                       stream_options = options)
}

#' Read JDBC Stream
#'
#' Reads a JDBC stream as a Spark dataframe stream.
#'
#' @inheritParams stream_read_csv
#'
#' @family Spark stream serialization
#'
#' @export
stream_read_jdbc <- function(sc,
                             path,
                             name = NULL,
                             columns = NULL,
                             options = list(),
                             ...)
{
  spark_require_version(sc, "2.0.0", "Spark streaming")

  name <- name %||% random_string("sparklyr_tmp_")

  stream_read_generic(sc,
                      path = path,
                      type = "jdbc",
                      name = name,
                      columns = columns,
                      stream_options = options)
}

#' Write JDBC Stream
#'
#' Writes a Spark dataframe stream into an JDBC stream.
#'
#' @inheritParams stream_write_memory
#'
#' @family Spark stream serialization
#'
#' @examples
#' \dontrun{
#'
#' sc <- spark_connect(master = "local")
#'
#' sdf_len(sc, 10) %>% spark_write_orc("orc-in")
#'
#' stream <- stream_read_parquet(sc, "orc-in") %>% stream_write_parquet("orc-out")
#'
#' stop_stream(stream)
#'
#' }
#'
#' @export
stream_write_jdbc <- function(x,
                              name = random_string("sparklyr_tmp_"),
                              mode = c("append", "complete", "update"),
                              trigger = stream_trigger_interval(interval = 5000),
                              checkpoint = file.path("checkpoints", name, random_string("")),
                              options = list(),
                              ...)
{
  spark_require_version(spark_connection(x), "2.0.0", "Spark streaming")

  sc <- spark_connection(x)

  stream_write_generic(x,
                       path = name,
                       type = "jdbc",
                       mode = mode,
                       trigger = trigger,
                       checkpoint = checkpoint,
                       stream_options = options)
}