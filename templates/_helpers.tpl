{{/*
Returns "true" when containers run with a read-only root filesystem, "false" otherwise.
Only applies when RestrictedSecurityMode is true. RestrictedSecurityModeReadOnly defaults to true when not set.
When "false", the writable emptyDir volumes and the init containers copying image files into them are not created.
*/}}
{{- define "imaging.readOnlyRootFS" -}}
{{- if and .Values.RestrictedSecurityMode (ne (toString .Values.RestrictedSecurityModeReadOnly) "false") -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}
