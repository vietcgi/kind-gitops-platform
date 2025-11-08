{{/*
Render resource requests and limits based on profile
Profiles: small, medium, large, daemonset

Usage: {{ include "platform-library.resources" (dict "profile" "medium" "overrides" .Values.resources "context" $) }}
*/}}
{{- define "platform-library.resources" -}}
{{- $profiles := dict "small" (dict "requests" (dict "cpu" "50m" "memory" "64Mi") "limits" (dict "cpu" "200m" "memory" "256Mi")) "medium" (dict "requests" (dict "cpu" "100m" "memory" "256Mi") "limits" (dict "cpu" "500m" "memory" "1Gi")) "large" (dict "requests" (dict "cpu" "200m" "memory" "512Mi") "limits" (dict "cpu" "1000m" "memory" "2Gi")) "daemonset" (dict "requests" (dict "cpu" "100m" "memory" "512Mi") "limits" (dict "cpu" "1000m" "memory" "1024Mi")) }}
{{- $profile := index $profiles .profile }}
{{- $resources := merge .overrides $profile }}
resources:
  requests:
    cpu: {{ $resources.requests.cpu | quote }}
    memory: {{ $resources.requests.memory | quote }}
  limits:
    cpu: {{ $resources.limits.cpu | quote }}
    memory: {{ $resources.limits.memory | quote }}
{{- end }}

{{/*
Quick resource profile helper
Usage: resources: {{ include "platform-library.resourceProfile" "medium" }}
*/}}
{{- define "platform-library.resourceProfile" -}}
{{- if eq . "small" }}
requests:
  cpu: "50m"
  memory: "64Mi"
limits:
  cpu: "200m"
  memory: "256Mi"
{{- else if eq . "medium" }}
requests:
  cpu: "100m"
  memory: "256Mi"
limits:
  cpu: "500m"
  memory: "1Gi"
{{- else if eq . "large" }}
requests:
  cpu: "200m"
  memory: "512Mi"
limits:
  cpu: "1000m"
  memory: "2Gi"
{{- else if eq . "daemonset" }}
requests:
  cpu: "100m"
  memory: "512Mi"
limits:
  cpu: "1000m"
  memory: "1024Mi"
{{- end }}
{{- end }}
