## Kaniko build Job template — driven by labops/kaniko/build.sh.
##
## Placeholders (substituted by build.sh):
##   @JOB_NAME@         unique Job name (e.g. hermes-build-abc1234-12345)
##   @REPO_URL@         GitHub repo without scheme (e.g. github.com/apnex/hermes.git)
##   @REVISION@         git ref (branch, tag, or full SHA)
##   @CONTEXT_SUBDIR@   subdir within repo containing the Dockerfile + context
##   @DOCKERFILE@       path to Dockerfile relative to context subdir
##   @DESTINATION@      target image:tag (e.g. 192.168.1.250:5000/hermes:abc1234)
apiVersion: batch/v1
kind: Job
metadata:
  name: @JOB_NAME@
  namespace: kaniko
  labels:
    app: kaniko
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600    # auto-clean completed/failed Jobs after 1h
  template:
    metadata:
      labels:
        app: kaniko
        job: @JOB_NAME@
    spec:
      restartPolicy: Never
      containers:
        - name: kaniko
          image: gcr.io/kaniko-project/executor:v1.24.0
          args:
            - "--context=git://@REPO_URL@#refs/heads/@REVISION@"
            - "--context-sub-path=@CONTEXT_SUBDIR@"
            - "--dockerfile=@DOCKERFILE@"
            - "--destination=@DESTINATION@"
            - "--insecure"
            - "--skip-tls-verify"
            - "--cache=true"
            - "--cache-repo=192.168.1.250:5000/kaniko-cache"
            - "--snapshot-mode=redo"
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "4"
              memory: "8Gi"
