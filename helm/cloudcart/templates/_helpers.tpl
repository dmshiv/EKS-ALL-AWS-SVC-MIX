{{- define "cloudcart.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/part-of: cloudcart
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- end -}}

{{- define "cloudcart.selector" -}}
app.kubernetes.io/name: {{ . }}
{{- end -}}

{{/* Image reference. Immutable tag from global.imageTag; fails the render if someone sets "latest". */}}
{{- define "cloudcart.image" -}}
{{- if eq .root.Values.global.imageTag "latest" -}}
{{- fail "global.imageTag must be an immutable tag (v1.0.0, git sha, build number), never latest" -}}
{{- end -}}
{{ .root.Values.global.imageRegistry }}/{{ .svc.image }}:{{ .root.Values.global.imageTag }}
{{- end -}}
