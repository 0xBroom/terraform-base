resource "google_logging_metric" "cloud-sql-monitoring" {
  name = format("%s--cloud-sql-monitoring", local.m_base_name_medium)

  description = "Cloud SQL Monitoring"
  filter      = "protoPayload.methodName=\"cloudsql.instances.update\" OR protoPayload.methodName=\"cloudsql.instances.create\" OR protoPayload.methodName=\"cloudsql.instances.delete\""
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
