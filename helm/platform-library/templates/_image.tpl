{{/*
Image template - standardized image configuration
Usage: {{ include "platform-library.image" (dict "repository" "ghcr.io/example" "tag" "v1.0" "context" $) }}
*/}}
{{- define "platform-library.image" -}}
image: {{ .repository }}:{{ .tag | default "latest" }}
imagePullPolicy: {{ .pullPolicy | default "IfNotPresent" }}
{{- end }}

{{/*
Full image reference
Usage: {{ include "platform-library.imageRef" (dict "repository" "ghcr.io/example" "tag" "v1.0" "context" $) }}
*/}}
{{- define "platform-library.imageRef" -}}
{{ .repository }}:{{ .tag | default "latest" }}
{{- end }}
