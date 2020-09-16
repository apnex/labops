.items? |
if (length > 0) then
	map(select((.status.loadBalancer.ingress | length) != 0)) | # filter for external IPs
	map(
		.status.loadBalancer.ingress[0].ip as $externalIP
		| .spec.ports[] |
		.externalIP |= $externalIP
	) |
	map(
		"-p "
			+ .protocol +
		" --dport "
			+ (.port|tostring) +
		" -j DNAT --to "
			+ .externalIP + ":" + (.port|tostring)
	)
else empty end
