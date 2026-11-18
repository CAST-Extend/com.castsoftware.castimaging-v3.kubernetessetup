{{/*
Short hash suffix for one-shot Job names. A Job's spec.template is immutable, so changing it in place
(helm upgrade, or Argo CD even with Replace=true) is rejected. Changing the name whenever the chart version,
the values or the Job's script change makes Helm/Argo CD create a new Job and prune the old one instead of
patching it.

Usage: include "imaging.jobSuffix" (list . "<configmap template file>" "<script key>")
The script is read from the rendered ConfigMap, so only that key is hashed: editing another script of the
same ConfigMap does not re-run the Job.
*/}}
{{- define "imaging.jobSuffix" -}}
{{- $root := index . 0 -}}
{{- $script := "" -}}
{{- if gt (len .) 2 -}}
{{- $key := index . 2 -}}
{{- $rendered := include (printf "%s/%s" $root.Template.BasePath (index . 1)) $root -}}
{{- range regexSplit "(?m)^---\\s*$" $rendered -1 -}}
{{- $doc := fromYaml . -}}
{{- if and $doc.data (hasKey $doc.data $key) -}}
{{- $script = index $doc.data $key -}}
{{- end -}}
{{- end -}}
{{- if not $script -}}
{{- fail (printf "imaging.jobSuffix: key %q not found in %s" $key (index . 1)) -}}
{{- end -}}
{{- end -}}
{{- printf "%s-%s-%s" $root.Chart.Version (toYaml $root.Values) $script | sha256sum | trunc 8 -}}
{{- end -}}

{{/*
Custom Dashboards configuration files (see files/dashboards-config/README.md).
files/dashboards-config/ mirrors /app/resources/config/ in the dashboards-v3 image: every file found there
(except README.md) is mounted at the same relative path.
Output (YAML): <ConfigMap key>: {src: <chart file path>, mount: <path in the container>}
*/}}
{{- define "imaging.dashboardsConfigFiles" -}}
{{- $root := "files/dashboards-config/" -}}
{{- $files := dict -}}
{{- range $path, $_ := .Files.Glob (printf "%s**" $root) -}}
{{- if ne $path (printf "%sREADME.md" $root) -}}
{{- $rel := trimPrefix $root $path -}}
{{- $key := replace "/" "__" $rel -}}
{{- if not (regexMatch "^[-._a-zA-Z0-9]+$" $key) -}}
{{- fail (printf "%s: file and folder names may only contain letters, digits, '-', '_' and '.'" $path) -}}
{{- end -}}
{{- $_ := set $files $key (dict "src" $path "mount" (printf "/app/resources/config/%s" $rel)) -}}
{{- end -}}
{{- end -}}
{{- toYaml $files -}}
{{- end -}}
