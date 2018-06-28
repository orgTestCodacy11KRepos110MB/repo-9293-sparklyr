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
    default = {
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

stream_write_generic <- function(x, path, type, trigger, checkpoint, stream_options)
{
  sdf <- spark_dataframe(x)
  sc <- spark_connection(x)

  if (!invoke(sdf, "isStreaming"))
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
    invoke("trigger", trigger) %>%
    invoke("start") %>%
    stream_class() %>%
    stream_validate()
}

#' Read a CSV Stream into a Spark DataFrame
#'
#' Read a tabular data stream into a Spark DataFrame.
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
                            infer_schema = TRUE,
                            delimiter = ",",
                            quote = "\"",
                            escape = "\\",
                            charset = "UTF-8",
                            null_value = NULL,
                            options = list(),
                            ...)
{
  spark_require_version(sc, "2.0.0")

  name <- name %||% random_string("sparklyr_tmp_")

  streamOptions <- spark_csv_options(header,
                                     infer_schema,
                                     delimiter,
                                     quote,
                                     escape,
                                     charset,
                                     null_value,
                                     options)

  stream_read_generic(sc,
                      path = path,
                      type = "csv",
                      name = name,
                      columns = columns,
                      stream_options = streamOptions)
}

#' Write a Spark DataFrame into CSV Stream
#'
#' Writes a Spark DataFrame to a tabular (typically, comma-separated) stream.
#'
#' @inheritParams spark_write_csv
#'
#' @param checkpoint The location where the system will write all the checkpoint
#' information to guarantee end-to-end fault-tolerance.
#'
#' @family Spark stream serialization
#'
#' @export
stream_write_csv <- function(x,
                             path,
                             trigger = stream_trigger_interval(interval = 5000),
                             checkpoint = file.path(path, "checkpoint"),
                             header = TRUE,
                             columns = NULL,
                             infer_schema = TRUE,
                             delimiter = ",",
                             quote = "\"",
                             escape = "\\",
                             charset = "UTF-8",
                             null_value = NULL,
                             options = list(),
                             ...)
{
  spark_require_version(spark_connection(x), "2.0.0")

  streamOptions <- spark_csv_options(header,
                                     infer_schema,
                                     delimiter,
                                     quote,
                                     escape,
                                     charset,
                                     null_value,
                                     options)

  stream_write_generic(x,
                       path = path,
                       type = "csv",
                       trigger = trigger,
                       checkpoint = checkpoint,
                       stream_options = streamOptions)
}

#' Write a Spark DataFrame into Memory
#'
#' Writes a Spark DataFrame into memory.
#'
#' @inheritParams stream_write_csv
#'
#' @family Spark stream serialization
#'
#' @examples
#' \dontrun{
#'
#' sc <- spark_connect(master = "local")
#'
#' dir.crate("iris-in")
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
                                trigger = stream_trigger_interval(interval = 5000),
                                checkpoint = file.path("checkpoints", name),
                                infer_schema = TRUE,
                                options = list(),
                                ...)
{
  spark_require_version(spark_connection(x), "2.0.0")

  sc <- spark_connection(x)

  stream_write_generic(x,
                       path = name,
                       type = "memory",
                       trigger = trigger,
                       checkpoint = checkpoint,
                       stream_options = options)
}