{{/*
Standard service configuration
Usage: {{ include "platform-library.service" (dict "type" "ClusterIP" "port" 8080 "targetPort" 8080) }}
*/}}
{{- define "platform-library.service" -}}
type: {{ .type | default "ClusterIP" }}
{{- if .port }}
port: {{ .port }}
{{- end }}
{{- if .targetPort }}
targetPort: {{ .targetPort }}
{{- end }}
{{- if .nodePort }}
nodePort: {{ .nodePort }}
{{- end }}
{{- if .selector }}
selector:
  {{- toYaml .selector | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Load balancer service configuration
Usage: {{ include "platform-library.loadBalancerService" (dict "port" 80 "targetPort" 8080 "loadBalancerClass" "my-lb") }}
*/}}
{{- define "platform-library.loadBalancerService" -}}
type: LoadBalancer
{{- if .loadBalancerClass }}
spec:
  loadBalancerClass: {{ .loadBalancerClass }}
{{- end }}
port: {{ .port }}
targetPort: {{ .targetPort }}
{{- if .protocol }}
protocol: {{ .protocol }}
{{- end }}
{{- end }}
