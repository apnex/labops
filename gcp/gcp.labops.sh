## GCP load-balancer configuration for labops.sh
fwd -> vip (ssl) -> map -> svc -> neg -> end

## create external network-endpoint-group
gcloud compute network-endpoint-groups create neg-github-raw --network-endpoint-type="internet-fqdn-port" --global

## add-endpoint to network-endpoint-group
gcloud compute network-endpoint-groups update neg-github-raw --add-endpoint="fqdn=raw.githubusercontent.com,port=443" --global

## create external network-endpoint-group
gcloud compute network-endpoint-groups create neg-github --network-endpoint-type="internet-fqdn-port" --global

## add-endpoint to network-endpoint-group
gcloud compute network-endpoint-groups update neg-github --add-endpoint="fqdn=github.com,port=443" --global

## show group
gcloud compute network-endpoint-groups list --global

## show contents
gcloud compute network-endpoint-groups list-network-endpoints neg-github-raw --global
gcloud compute network-endpoint-groups list-network-endpoints neg-github --global

## create backend-service
gcloud compute backend-services create svc-github-raw --enable-cdn --protocol=HTTPS --global

## create backend-service
gcloud compute backend-services create svc-github --enable-cdn --protocol=HTTPS --global

## add network-endpoint-group to backend-service
gcloud compute backend-services add-backend svc-github-raw --network-endpoint-group "neg-github-raw" --global-network-endpoint-group --global

## add network-endpoint-group to backend-service
gcloud compute backend-services add-backend svc-github --network-endpoint-group "neg-github" --global-network-endpoint-group --global

## create url map
gcloud compute url-maps create map-labops --default-service svc-github-raw --global

## create target-https-proxy
gcloud compute target-https-proxies create vip-labops --url-map=map-labops --ssl-certificates=ssl-labops-sh --global

## create forwarding-rule
gcloud compute forwarding-rules create fwd-labops --ip-protocol=TCP --ports=443 --target-https-proxy=vip-labops --address=ip4-labops --global

## verify certificate
gcloud compute target-https-proxies describe vip-labops --format="get(sslCertificates)" --global

## reserved static external ip address
gcloud compute addresses create ip4-labops --ip-version=IPV4 --global

## Craft url-map-spec
cat << EOF > /tmp/map-labops-redirect.yaml
kind: compute#urlMap
name: map-labops-redirect
defaultUrlRedirect:
   redirectResponseCode: MOVED_PERMANENTLY_DEFAULT
   httpsRedirect: True
EOF

## Create new URL map for HTTP->HTTPS
gcloud compute url-maps import map-labops-redirect \
   --source /tmp/map-labops-redirect.yaml \
   --global

## Create a new HTTP-PROXY
gcloud compute target-http-proxies create vip-labops-http \
   --url-map=map-labops-redirect \
   --global

## HTTP->HTTPS redirect
gcloud compute forwarding-rules create fwd-labops-http \
   --address=ip4-labops \
   --target-http-proxy=vip-labops-http \
   --ports=80 \
   --global

## Verify ip4-address
gcloud compute addresses describe ip4-address \
    --format="get(address)" \
    --global

## Craft map-labops spec
cat << EOF > /tmp/map-labops.yaml
defaultRouteAction:
  urlRewrite:
    pathPrefixRewrite: /apnex/labops
defaultService: https://www.googleapis.com/compute/v1/projects/labops/global/backendServices/svc-github-raw
fingerprint: uE9-fSTCJRo=
hostRules:
- hosts:
  - labops.sh
  pathMatcher: path-matcher-1
kind: compute#urlMap
name: map-labops
pathMatchers:
- defaultUrlRedirect:
    hostRedirect: github.com
    httpsRedirect: true
    prefixRedirect: /apnex/labops
    redirectResponseCode: MOVED_PERMANENTLY_DEFAULT
  name: path-matcher-1
  pathRules:
  - paths:
    - /docker/*
    routeAction:
      urlRewrite:
        hostRewrite: raw.githubusercontent.com
        pathPrefixRewrite: /apnex/labops/master/docker/
    service: https://www.googleapis.com/compute/v1/projects/labops/global/backendServices/svc-github-raw
  - paths:
    - /rke/*
    routeAction:
      urlRewrite:
        hostRewrite: raw.githubusercontent.com
        pathPrefixRewrite: /apnex/labops/master/rke/
    service: https://www.googleapis.com/compute/v1/projects/labops/global/backendServices/svc-github-raw
