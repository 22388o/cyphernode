#!/bin/sh

. ./trace.sh
. ./sendtobitcoinnode.sh
. ./sql.sh
. ./blockchainrpc.sh

compute_fees() {
  local pruned=${WATCHER_BTC_NODE_PRUNED}
  if [ "${pruned}" = "true" ]; then
    trace "[compute_fees]  pruned=${pruned}"
    # We want null instead of 0.00000000 in this case.
    echo "null"
    return
  fi

  local txid=${1}

  # Let's reuse the file created in confirmation...
  local tx_raw_details=$(cat rawtx-${txid}-$$.blob)
  trace "[compute_fees]  tx_raw_details=${tx_raw_details}"
  local vin_total_amount=$(compute_vin_total_amount "${tx_raw_details}")

  local vout_total_amount=0
  local vout_value
  local vout_values=$(echo "${tx_raw_details}" | jq ".result.vout[].value")
  for vout_value in ${vout_values}
  do
    vout_total_amount=$(awk "BEGIN { printf(\"%.8f\", ${vout_total_amount}+${vout_value}); exit }")
  done

  trace "[compute_fees]  vin total amount=${vin_total_amount}"
  trace "[compute_fees] vout total amount=${vout_total_amount}"

  local fees=$(awk "BEGIN { printf(\"%.8f\", ${vin_total_amount}-${vout_total_amount}); exit }")
  trace "[compute_fees] fees=${fees}"

  echo "${fees}"
}

compute_vin_total_amount()
{
  trace "Entering compute_vin_total_amount()..."

  local main_tx=${1}
  local vin_txids_vout=$(echo "${main_tx}" | jq '.result.vin[] | ((.txid + "-") + (.vout | tostring))')
  trace "[compute_vin_total_amount] vin_txids_vout=${vin_txids_vout}"
  local returncode
  local vin_txid_vout
  local vin_txid
  local vin_raw_tx
  local vin_vout_amount=0
  local vout
  local vin_total_amount=0
  local vin_hash
  local vin_confirmations
  local vin_timereceived
  local vin_vsize
  local vin_blockhash
  local vin_blockheight
  local vin_blocktime
  local txid_already_inserted=true

  for vin_txid_vout in ${vin_txids_vout}
  do
    vin_txid=$(echo "${vin_txid_vout}" | tr -d '"' | cut -d '-' -f1)
    vin_raw_tx=$(get_rawtransaction "${vin_txid}" | tr -d '\n')
    returncode=$?
    if [ "${returncode}" -ne 0 ]; then
      return ${returncode}
    fi
    vout=$(echo "${vin_txid_vout}" | tr -d '"' | cut -d '-' -f2)
    trace "[compute_vin_total_amount] vout=${vout}"
    vin_vout_amount=$(echo "${vin_raw_tx}" | jq ".result.vout[] | select(.n == ${vout}) | .value" | awk '{ printf "%.8f", $0 }')
    trace "[compute_vin_total_amount] vin_vout_amount=${vin_vout_amount}"
    vin_total_amount=$(awk "BEGIN { printf(\"%.8f\", ${vin_total_amount}+${vin_vout_amount}); exit}")
    trace "[compute_vin_total_amount] vin_total_amount=${vin_total_amount}"
    vin_hash=$(echo "${vin_raw_tx}" | jq -r ".result.hash")
    vin_confirmations=$(echo "${vin_raw_tx}" | jq ".result.confirmations")
    vin_timereceived=$(echo "${vin_raw_tx}" | jq ".result.time")
    vin_size=$(echo "${vin_raw_tx}" | jq ".result.size")
    vin_vsize=$(echo "${vin_raw_tx}" | jq ".result.vsize")
    vin_blockhash=$(echo "${vin_raw_tx}" | jq -r ".result.blockhash")
    vin_blockheight=$(echo "${vin_raw_tx}" | jq ".result.blockheight")
    vin_blocktime=$(echo "${vin_raw_tx}" | jq ".result.blocktime")

    # Let's insert the vin tx in the DB just in case it would be useful
    sql "INSERT INTO tx (txid, hash, confirmations, timereceived, size, vsize, blockhash, blockheight, blocktime)"\
" VALUES ('${vin_txid}', '${vin_hash}', ${vin_confirmations}, ${vin_timereceived}, ${vin_size}, ${vin_vsize}, '${vin_blockhash}', ${vin_blockheight}, ${vin_blocktime})"\
" ON CONFLICT (txid) DO"\
" UPDATE SET blockhash='${vin_blockhash}', blockheight=${vin_blockheight}, blocktime=${vin_blocktime}, confirmations=${vin_confirmations}"
    trace_rc $?
  done

  echo "${vin_total_amount}"

  return 0
}

case "${0}" in *computefees.sh) compute_vin_total_amount $@;; esac
