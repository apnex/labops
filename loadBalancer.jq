.items? |
if (length > 0) then
	map(select((.status.loadBalancer.ingress | length) != 0)) | # filter for external IPs
	map({
		"ports": .spec.ports,
		"ingress": .status.loadBalancer.ingress
	}) |
	map(
		"-p "
			+ .ports[0].protocol +
		" --dport "
			+ (.ports[0].port|tostring) +
		" -j DNAT --to "
			+ .ingress[0].ip + ":" + (.ports[0].targetPort|tostring)
	)
else empty end
