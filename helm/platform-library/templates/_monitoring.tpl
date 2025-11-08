{{/*
ServiceMonitor configuration for Prometheus
Usage: {{ include "platform-library.serviceMonitor" (dict "enabled" true "namespace" "monitoring" "interval" "30s") }}
*/}}
{{- define "platform-library.serviceMonitor" -}}
{{- if .enabled }}
serviceMonitor:
  enabled: true
  namespace: {{ .namespace | default "monitoring" }}
  interval: {{ .interval | default "30s" }}
  {{- if .scrapeTimeout }}
  scrapeTimeout: {{ .scrapeTimeout | quote }}
  {{- end }}
  {{- if .labels }}
  labels:
    {{- toYaml .labels | nindent 4 }}
  {{- end }}
{{- else }}
serviceMonitor:
  enabled: false
{{- end }}
{{- end }}

{{/*
PrometheusRule configuration
Usage: {{ include "platform-library.prometheusRule" (dict "enabled" true "namespace" "monitoring") }}
*/}}
{{- define "platform-library.prometheusRule" -}}
{{- if .enabled }}
prometheusRule:
  enabled: true
  namespace: {{ .namespace | default "monitoring" }}
  {{- if .labels }}
  labels:
    {{- toYaml .labels | nindent 4 }}
  {{- end }}
{{- else }}
prometheusRule:
  enabled: false
{{- end }}
{{- end }}
