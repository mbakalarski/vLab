#!/usr/bin/env bats


basedir="examples/srlinux"
manifests=("bridge_*.yaml" "${ROUTER}_hw.yaml" "${ROUTER}.yaml")


setup_file() {
    for manifest in ${manifests[@]}; do
        kubectl apply -f "${basedir}/manifests/${manifest}"
    done
    podCIDR=$(kubectl get nodes vlab-control-plane -o jsonpath='{.spec.podCIDR}')
    node_address=$(kubectl get nodes vlab-control-plane -o jsonpath='{.status.addresses[0].address}')
    sudo ip route del ${podCIDR} || true
    sudo ip route add ${podCIDR} via ${node_address}

    kubectl wait --for=jsonpath='{.status.phase}'=Running --timeout=240s pod/${ROUTER}

    timeout=120

    while [[ ${timeout} -ge 0 ]]
    do
        echo "# ${timeout} " >&3
        ip=$(kubectl exec ${ROUTER} -- bash -c 'ip netns exec srbase-mgmt ip -br addr show dev mgmt0.0' | awk '{printf $3}' | awk -F'/' '{printf $1}') || true
        pod_prefix=$(echo ${podCIDR} | awk -F'.' -e '{printf $1"."$2"."$3}')
        if [[ $ip =~ "$pod_prefix" ]]; then break; fi
        sleep 1
        timeout=$(($timeout-1))
    done

    kubectl cp "${basedir}/tests/mgmt_config.cli" "${ROUTER}:/mgmt_config.cli"
    kubectl exec "$ROUTER" -- sr_cli source /mgmt_config.cli
    kubectl exec "$ROUTER" -- bash -c "rm -f /mgmt_config.cli"
}


teardown_file() {
    for manifest in ${manifests[@]}; do
        kubectl delete -f ${basedir}/manifests/${manifest}
    done
}


@test "ping to mgmt $ROUTER success" {
    ip=$(kubectl exec ${ROUTER} -- bash -c 'ip netns exec srbase-mgmt ip -br addr show dev mgmt0.0' | awk '{printf $3}' | awk -F'/' '{printf $1}')
    run ping -c3 "$ip"
    [ "$status" -eq 0 ]
}
