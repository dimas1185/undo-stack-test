#!/bin/bash
#EOSIO_CONTRACTS_DIRECTORY="$HOME/Work/eosio.contracts/build/contracts"
EOSIO_CONTRACTS_DIRECTORY="$HOME/Downloads/build/contracts"
EOS_TEST_CONTRACTS="$HOME/Work/eos/unittests/test-contracts"
NUMBER_OF_PRODUCERS=8
CHAINBASE_PRODS=6
DUPLICATE_INDEX=8
DUPLICATE_CNT=2
IDLE_TIME=360
OLD_EOS_PATH=$HOME/Work/eos_copy/build/bin

function backing_store {
   if [ $1 -le $CHAINBASE_PRODS ]
   then
      echo "chainbase"
   else
      echo "rocksdb"
   fi
}

function should_duplicate {
   if [ $1 -eq $DUPLICATE_INDEX ]
   then
      echo 1
   fi
}

function producer_name {
   if [ $1 -le 5 ]
   then
      NAME="prod.$1"
   else
      CNT=$1
      NAME="prod.5"
      while [ $CNT -gt 5 ]
      do
         CNT=$(( $CNT - 5 ))
         if [ $CNT -gt 5 ]
         then
            NAME="${NAME}.5"
         else
            NAME="${NAME}.${CNT}"
         fi
      done
   fi

   echo $NAME
}

function get_priv_key {
   cat $1 | sed -n -e 's/Private key: //p'
}

function get_pub_key {
   cat $1 | sed -n -e 's/Public key: //p'
}

function activate_feature {
   curl --request POST \
      --url http://127.0.0.1:$1/v1/producer/schedule_protocol_feature_activations \
      -d "{\"protocol_features_to_activate\": [\"$2\"]}" | python -m json.tool
}

function send_trx {
   curl --request POST \
        --url http://127.0.0.1:$1/v1/chain/send_transaction \
        -d ''"$2"'' | python -m json.tool
}

function peers_cl {
   BASE_PORT=$3
   for i in $(seq 1 $2)
   do
      if [ $i -ne $1 ]
      then
         PORT=$(( $BASE_PORT + $i ))
         echo "--p2p-peer-address 0.0.0.0:$PORT "
      fi
   done
}

function old_nodeos {
   if [ $1 -le $(( $NUMBER_OF_PRODUCERS / 2 )) ]
   then
      echo 1
   fi
}

function nodeos_path {
   if [ $(old_nodeos $1) ]
   then
      echo "$OLD_EOS_PATH/nodeos"
   else
      echo "nodeos"
   fi
}

function chain_id {
   cleos get info | sed -n 's/[[:space:]]*\"chain_id\":[[:space:]]*\"\(.*\)\",[[:space:]]*/\1/p'
}

pkill nodeos
rm -rf ./data* ./protocol_features* ./*.keys ./gen_conf* ./*.log ./*trx.json

pkill keosd
rm -rf ~/eosio-wallet/df*

keosd > keosd.log 2>&1 &

cleos wallet create -n df -f ./wallet.keys
WALLET_PASSWORD=$(cat ./wallet.keys)

#eosio private key
cleos wallet import -n df --private-key 5KQwrPbwdL6PhXujxW37FSSQZ1JiwsST4cqQzDeyXtP79zkvFD3

declare -a PRIV_KEYS=()
declare -a PUB_KEYS=()

for i in $(seq 1 $NUMBER_OF_PRODUCERS)
do
   echo "creating keys for producer number $i"
   cleos create key -f "./eosio.prods${i}.keys"
   PRIV_KEYS[$i]=$(get_priv_key ./eosio.prods${i}.keys)
   PUB_KEYS[$i]=$(get_pub_key ./eosio.prods${i}.keys)
   cleos wallet import -n df --private-key ${PRIV_KEYS[$i]}
done

cleos create key -f ./eosio.bpay.keys
cleos wallet import -n df --private-key $(get_priv_key ./eosio.bpay.keys)
cleos create key -f ./eosio.msig.keys
cleos wallet import -n df --private-key $(get_priv_key ./eosio.msig.keys)
cleos create key -f ./eosio.names.keys
cleos wallet import -n df --private-key $(get_priv_key ./eosio.names.keys)
cleos create key -f ./eosio.ram.keys
cleos wallet import -n df --private-key $(get_priv_key ./eosio.ram.keys)
cleos create key -f ./eosio.ramfee.keys
cleos wallet import -n df --private-key $(get_priv_key ./eosio.ramfee.keys)
cleos create key -f ./eosio.saving.keys
cleos wallet import -n df --private-key $(get_priv_key ./eosio.saving.keys)
cleos create key -f ./eosio.stake.keys
cleos wallet import -n df --private-key $(get_priv_key ./eosio.stake.keys)
cleos create key -f ./eosio.token.keys
cleos wallet import -n df --private-key $(get_priv_key ./eosio.token.keys)
cleos create key -f ./eosio.vpay.keys
cleos wallet import -n df --private-key $(get_priv_key ./eosio.vpay.keys)
cleos create key -f ./eosio.rex.keys
cleos wallet import -n df --private-key $(get_priv_key ./eosio.rex.keys)

cleos wallet open -n df
cleos wallet unlock -n df --password $WALLET_PASSWORD

#generate genesis. starting from 5th as it is 2.1 nodeos
echo "generating genesis..."
cat ./genesis_template.json | sed -e "s/REPLACE_WITH_PRIVATE_KEY/${PUB_KEYS[5]}/g" > ./genesis.json

echo "generating config..."
for i in $(seq 1 $NUMBER_OF_PRODUCERS)
do
   mkdir -p ./gen_conf${i}
   mkdir -p ./conf${i}
   echo "generating genesis config for producer number $i with backing-store $(backing_store $i)"
   cat ./genesis_config_template.ini | sed -e "s/PUB_KEY/${PUB_KEYS[$i]}/g" | sed -e "s/PRIV_KEY/${PRIV_KEYS[$i]}/g" | sed -e "s/BK_STORE/$(backing_store $i)/g" > ./gen_conf${i}/config.ini
   if [ $(old_nodeos $i) ]
   then
      cat ./gen_conf${i}/config.ini | sed -e "s/backing-store/#backing-store/g" > ./gen_conf${i}/config2.ini
      cp ./gen_conf${i}/config2.ini ./gen_conf${i}/config.ini
   fi
   cat ./config_template.ini | sed -e "s/PUB_KEY/${PUB_KEYS[$i]}/g" | sed -e "s/PRIV_KEY/${PRIV_KEYS[$i]}/g" | sed -e "s/BK_STORE/$(backing_store $i)/g" > ./conf${i}/config.ini
   if [ $(old_nodeos $i) ]
   then
      cat ./conf${i}/config.ini | sed -e "s/backing-store/#backing-store/g" > ./conf${i}/config2.ini
      cp ./conf${i}/config2.ini ./conf${i}/config.ini
   fi
   if [ $(should_duplicate $i) ]
   then
      for j in $(seq 1 $DUPLICATE_CNT)
      do
         echo "making $j duplicate for producer $i"
         mkdir -p ./gen_conf${i}_${j}
         mkdir -p ./conf${i}_${j}
         cp ./gen_conf${i}/config.ini ./gen_conf${i}_${j}/config.ini
         cp ./conf${i}/config.ini ./conf${i}_${j}/config.ini
      done
   fi
done


echo "creating new blockchain from genesis..."
for i in $(seq 1 $NUMBER_OF_PRODUCERS)
do
   echo "producer $i"
   $(nodeos_path $i) --genesis-json ./genesis.json \
          --data-dir ./data${i}     \
          --protocol-features-dir ./protocol_features${i} \
          --config-dir ./gen_conf${i} \
          > nodeos_${i}.log 2>&1 &
   if [ $(should_duplicate $i) ]
   then
      for j in $(seq 1 $DUPLICATE_CNT)
      do
         echo "producer $i duplicate $j"
         $(nodeos_path $i) --genesis-json ./genesis.json \
               --data-dir ./data${i}_${j}     \
               --protocol-features-dir ./protocol_features${i}_${j} \
               --config-dir ./gen_conf${i}_${j} \
               > nodeos_${i}_${j}.log 2>&1 &
      done
   fi
done
sleep 3
pkill nodeos

echo "starting eosio on 5th producer"
$(nodeos_path 5) -e -p eosio \
  --data-dir ./data5     \
  --protocol-features-dir ./protocol_features5 \
  --config-dir ./conf5 \
  --contracts-console   \
  --disable-replay-opts \
  --http-server-address 0.0.0.0:8888 \
  --p2p-listen-endpoint 0.0.0.0:9876 \
  --state-history-endpoint 0.0.0.0:8788 \
  -l ./logging.json \
  >> nodeos_5.log 2>&1 &
sleep 3

echo "creating system accounts..."
cleos create account eosio eosio.bpay $(get_pub_key eosio.bpay.keys) #-p eosio@active
cleos create account eosio eosio.msig $(get_pub_key eosio.msig.keys) #-p eosio@active
cleos create account eosio eosio.names $(get_pub_key eosio.names.keys) #-p eosio@active
cleos create account eosio eosio.ram $(get_pub_key eosio.ram.keys) #-p eosio@active
cleos create account eosio eosio.ramfee $(get_pub_key eosio.ramfee.keys) #-p eosio@active
cleos create account eosio eosio.saving $(get_pub_key eosio.saving.keys) #-p eosio@active
cleos create account eosio eosio.stake $(get_pub_key eosio.stake.keys) #-p eosio@active
cleos create account eosio eosio.token $(get_pub_key eosio.token.keys) #-p eosio@active
cleos create account eosio eosio.vpay $(get_pub_key eosio.vpay.keys) #-p eosio@active
cleos create account eosio eosio.rex $(get_pub_key eosio.rex.keys) #-p eosio@active

#PREACTIVATE_FEATURE
activate_feature 8888 "0ec7e080177b2c02b278d5088611686b49d739925a92d9bfcacd7fc6b74053bd"

sleep 3

#cleos set contract eosio $EOSIO_CONTRACTS_DIRECTORY/eosio.boot/

#sleep 5

#KV_DATABASE
#cleos push action eosio activate '["825ee6288fb1373eab1b5187ec2f04f6eacb39cb3a97f356a07c91622dd61d16"]' -p eosio
#WTMSIG_BLOCK_SIGNATURES
#cleos push action eosio activate '["299dcb6af692324b899b39f16d5a530a33062804e41f09dc97e9f156b4476707"]' -p eosio
#sleep 5

cleos set contract eosio $EOSIO_CONTRACTS_DIRECTORY/eosio.system/
sleep 3
cleos set contract eosio.msig $EOSIO_CONTRACTS_DIRECTORY/eosio.msig/
sleep 3
cleos set contract eosio.token $EOSIO_CONTRACTS_DIRECTORY/eosio.token/
sleep 3

#10bln
cleos push action eosio.token create '[ "eosio", "10000000000.0000 SYS" ]' -p eosio.token
#1bln
cleos push action eosio.token issue '[ "eosio", "10000000000.0000 SYS", "memo" ]' -p eosio
cleos push action eosio init '["0", "4,SYS"]' -p eosio@active

cleos push action eosio setpriv '["eosio.msig", 1]' -p eosio
sleep 3


for i in $(seq 1 $NUMBER_OF_PRODUCERS)
do
   PROD_NAME=$(producer_name $i)
   
   #10mm
   cleos system newaccount eosio --transfer $PROD_NAME ${PUB_KEYS[$i]} --stake-net "10000000.0000 SYS" --stake-cpu "10000000.0000 SYS" --buy-ram-kbytes 8192
   cleos system regproducer $PROD_NAME ${PUB_KEYS[$i]} https://dimon${i}.io 840 -p $PROD_NAME
   cleos system voteproducer prods $PROD_NAME $PROD_NAME -p $PROD_NAME
done

cleos transfer eosio prod.1 "1000.0000 SYS" -p eosio
cleos transfer eosio prod.2 "1000.0000 SYS" -p eosio

cleos system listproducers

# cleos transfer eosio eosio.saving "0.1 SYS" -p eosio -d --json-file ./unsigned_trx.json

# cat ./unsigned_trx.json | xargs -0 -J {} cleos convert pack_transaction --pack-action-data {} > ./packed_trx.json
# echo "packed transaction:"
# cat ./packed_trx.json

# cat ./packed_trx.json | sed -e "s/\(\"packed_trx\":[[:space:]]*\".*\)\(\"\)/\100000000\2/g" > ./packed_trail_trx.json
# echo "adding trailing zeros to unsigned trx:"
# cat ./packed_trail_trx.json

# send_trx 8888 ''"$(cat ./packed_trail_trx.json)"''

#resign eosio and other system accounts
cleos push action eosio updateauth '{"account": "eosio", "permission": "owner", "parent": "", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio.prods", "permission": "active"}}]}}' -p eosio@owner
cleos push action eosio updateauth '{"account": "eosio", "permission": "active", "parent": "owner", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio.prods", "permission": "active"}}]}}' -p eosio@active

cleos push action eosio updateauth '{"account": "eosio.bpay", "permission": "owner", "parent": "", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.bpay@owner
cleos push action eosio updateauth '{"account": "eosio.bpay", "permission": "active", "parent": "owner", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.bpay@active

cleos push action eosio updateauth '{"account": "eosio.msig", "permission": "owner", "parent": "", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.msig@owner
cleos push action eosio updateauth '{"account": "eosio.msig", "permission": "active", "parent": "owner", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.msig@active

cleos push action eosio updateauth '{"account": "eosio.names", "permission": "owner", "parent": "", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.names@owner
cleos push action eosio updateauth '{"account": "eosio.names", "permission": "active", "parent": "owner", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.names@active

cleos push action eosio updateauth '{"account": "eosio.ram", "permission": "owner", "parent": "", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.ram@owner
cleos push action eosio updateauth '{"account": "eosio.ram", "permission": "active", "parent": "owner", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.ram@active

cleos push action eosio updateauth '{"account": "eosio.ramfee", "permission": "owner", "parent": "", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.ramfee@owner
cleos push action eosio updateauth '{"account": "eosio.ramfee", "permission": "active", "parent": "owner", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.ramfee@active

cleos push action eosio updateauth '{"account": "eosio.saving", "permission": "owner", "parent": "", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.saving@owner
cleos push action eosio updateauth '{"account": "eosio.saving", "permission": "active", "parent": "owner", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.saving@active

cleos push action eosio updateauth '{"account": "eosio.stake", "permission": "owner", "parent": "", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.stake@owner
cleos push action eosio updateauth '{"account": "eosio.stake", "permission": "active", "parent": "owner", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.stake@active

cleos push action eosio updateauth '{"account": "eosio.token", "permission": "owner", "parent": "", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.token@owner
cleos push action eosio updateauth '{"account": "eosio.token", "permission": "active", "parent": "owner", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.token@active

cleos push action eosio updateauth '{"account": "eosio.vpay", "permission": "owner", "parent": "", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.vpay@owner
cleos push action eosio updateauth '{"account": "eosio.vpay", "permission": "active", "parent": "owner", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio", "permission": "active"}}]}}' -p eosio.vpay@active

sleep 3

pkill nodeos

for i in $(seq 1 $NUMBER_OF_PRODUCERS)
do
   PROD_NAME=$(producer_name $i)
   echo "starting producer $PROD_NAME"

   HTTP_PORT=$(( 8887 + $i ))
   LISTEN_ENDPOINT=$(( 9875 + $i ))
   PEERS_CL=$(peers_cl $i $NUMBER_OF_PRODUCERS 9875)
   SH_PORT=$(( 8787 + $i ))

   $(nodeos_path $i) -e -p $PROD_NAME \
         --data-dir ./data${i}     \
         --protocol-features-dir ./protocol_features${i} \
         --config-dir ./conf${i} \
         --contracts-console   \
         --disable-replay-opts \
         --http-server-address 0.0.0.0:$HTTP_PORT \
         --p2p-listen-endpoint 0.0.0.0:$LISTEN_ENDPOINT \
         $PEERS_CL \
         --state-history-endpoint 0.0.0.0:$SH_PORT \
         -l ./logging.json \
         >> nodeos_${i}.log 2>&1 &
   
   if [ $(should_duplicate $i) ]
   then
      for j in $(seq 1 $DUPLICATE_CNT)
      do
         HTTP_PORT=$(( $HTTP_PORT - 100 + $j ))
         LISTEN_ENDPOINT=$(( $LISTEN_ENDPOINT - 100 ))
         SH_PORT=$(( $SH_PORT - 100 ))
         $(nodeos_path $i) -e -p $PROD_NAME \
               --data-dir ./data${i}_${j}     \
               --protocol-features-dir ./protocol_features${i}_${j} \
               --config-dir ./conf${i}_${j} \
               --contracts-console   \
               --disable-replay-opts \
               --http-server-address 0.0.0.0:$HTTP_PORT \
               --p2p-listen-endpoint 0.0.0.0:$LISTEN_ENDPOINT \
               $PEERS_CL \
               $(peers_cl $j $DUPLICATE_CNT 9775) \
               --state-history-endpoint 0.0.0.0:$SH_PORT \
               -l ./logging.json \
               >> nodeos_${i}_${j}.log 2>&1 &
      done
   fi
done

sleep 200

for i in $(seq 1 $NUMBER_OF_PRODUCERS)
do
   cleos --url http://127.0.0.1:8892/ set contract $(producer_name $i) $EOS_TEST_CONTRACTS/get_table_test/
done
sleep 3

cleos get info

for i in $(seq 1 $NUMBER_OF_PRODUCERS)
do
   PROD_NAME=$(producer_name $i)
   cleos --url http://127.0.0.1:8892/ push action $PROD_NAME addnumobj '["2"]' -p $PROD_NAME
   cleos --url http://127.0.0.1:8892/ push action $PROD_NAME addnumobj '["5"]' -p $PROD_NAME 
   cleos --url http://127.0.0.1:8892/ push action $PROD_NAME addnumobj '["7"]' -p $PROD_NAME
   
   cleos --url http://127.0.0.1:8892/ push action $PROD_NAME addhashobj '["firstinput"]' -p $PROD_NAME
   cleos --url http://127.0.0.1:8892/ push action $PROD_NAME addhashobj '["secondinput"]' -p $PROD_NAME
   cleos --url http://127.0.0.1:8892/ push action $PROD_NAME addhashobj '["thirdinput"]' -p $PROD_NAME
done

sleep 3

PROD_NAME=$(producer_name 1)
cleos --url http://127.0.0.1:8892/ get table $PROD_NAME $PROD_NAME numobjs
cleos --url http://127.0.0.1:8892/ get table $PROD_NAME $PROD_NAME hashobjs

cleos get info

for i in $(seq 1 $NUMBER_OF_PRODUCERS)
do
   PROD_NAME=$(producer_name $i)
   cleos --url http://127.0.0.1:8892/ push action $PROD_NAME modifynumobj '["0"]' -p $PROD_NAME
   cleos --url http://127.0.0.1:8892/ push action $PROD_NAME erasenumobj '["2"]' -p $PROD_NAME
done

sleep 3
cleos get info

PROD_NAME=$(producer_name 1)
cleos --url http://127.0.0.1:8892/ get table $PROD_NAME $PROD_NAME numobjs
cleos --url http://127.0.0.1:8892/ get table $PROD_NAME $PROD_NAME hashobjs


cleos get info

echo "get balance:"
cleos get currency balance eosio.token prod.1 SYS
cleos get currency balance eosio.token prod.2 SYS
echo "-----------"

#sleep 200

#sending to v2.0.9
cleos --url http://127.0.0.1:8888/ transfer prod.1 prod.2 "0.1 SYS" -p prod.1 -d --json-file ./unsigned_trx.json

cat ./unsigned_trx.json | xargs -0 -J {} cleos convert pack_transaction --pack-action-data {} > ./packed_trx.json
echo "packed transaction:"
cat ./packed_trx.json

cat ./packed_trx.json | sed -e "s/\(\"packed_trx\":[[:space:]]*\".*\)\(\"\)/\100000000\2/g" > ./packed_trail_trx.json
echo "adding trailing zeros to unsigned trx:"
cat ./packed_trail_trx.json

send_trx 8888 ''"$(cat ./packed_trail_trx.json)"''

sleep 3

#sending to v2.1.0
cleos --url http://127.0.0.1:8892/ transfer prod.2 prod.1 "2.1 SYS" -p prod.2 -d --json-file ./unsigned_trx.json

cat ./unsigned_trx.json | xargs -0 -J {} cleos convert pack_transaction --pack-action-data {} > ./packed_trx.json
echo "packed transaction:"
cat ./packed_trx.json

cat ./packed_trx.json | sed -e "s/\(\"packed_trx\":[[:space:]]*\".*\)\(\"\)/\100000000\2/g" > ./packed_trail_trx.json
echo "adding trailing zeros to unsigned trx:"
cat ./packed_trail_trx.json

send_trx 8888 ''"$(cat ./packed_trail_trx.json)"''

sleep 5
cleos --url http://127.0.0.1:8888/ get info
cleos --url http://127.0.0.1:8892/ get info

echo "stopping all producers"
pkill nodeos

for i in $(seq 1 $NUMBER_OF_PRODUCERS)
do
   ls -lh ./data${i}/state/undo_stack.dat
   if [ $(should_duplicate $i) ]
   then
      for j in $(seq 1 $DUPLICATE_CNT)
      do
         ls -lh ./data${i}_${j}/state/undo_stack.dat
      done
   fi
done

cp -R ./data7 ./data7_copy

eosio-blocklog --blocks-dir ./data7_copy/blocks --as-json-array | grep "reversible"

for i in $(seq 1 $NUMBER_OF_PRODUCERS)
do
   PROD_NAME=$(producer_name $i)
   echo "restarting producer $PROD_NAME"

   HTTP_PORT=$(( 8887 + $i ))
   LISTEN_ENDPOINT=$(( 9875 + $i ))
   PEERS_CL=$(peers_cl $i $NUMBER_OF_PRODUCERS 9875)
   SH_PORT=$(( 8787 + $i ))

   $(nodeos_path $i) -e -p $PROD_NAME \
         --data-dir ./data${i}     \
         --protocol-features-dir ./protocol_features${i} \
         --config-dir ./conf${i} \
         --contracts-console   \
         --disable-replay-opts \
         --http-server-address 0.0.0.0:$HTTP_PORT \
         --p2p-listen-endpoint 0.0.0.0:$LISTEN_ENDPOINT \
         $PEERS_CL \
         --state-history-endpoint 0.0.0.0:$SH_PORT \
         -l ./logging.json \
         >> nodeos_${i}.log 2>&1 &
   
   if [ $(should_duplicate $i) ]
   then
      for j in $(seq 1 $DUPLICATE_CNT)
      do
         HTTP_PORT=$(( $HTTP_PORT - 100 + $j ))
         LISTEN_ENDPOINT=$(( $LISTEN_ENDPOINT - 100 ))
         SH_PORT=$(( $SH_PORT - 100 ))
         $(nodeos_path $i) -e -p $PROD_NAME \
               --data-dir ./data${i}_${j}     \
               --protocol-features-dir ./protocol_features${i}_${j} \
               --config-dir ./conf${i}_${j} \
               --contracts-console   \
               --disable-replay-opts \
               --http-server-address 0.0.0.0:$HTTP_PORT \
               --p2p-listen-endpoint 0.0.0.0:$LISTEN_ENDPOINT \
               $PEERS_CL \
               $(peers_cl $j $DUPLICATE_CNT 9775) \
               --state-history-endpoint 0.0.0.0:$SH_PORT \
               -l ./logging.json \
               >> nodeos_${i}_${j}.log 2>&1 &
      done
   fi
done

ELAPSED=0
while [ $ELAPSED -lt 100 ]
do
   sleep $(( $IDLE_TIME / 100 ))
   ELAPSED=$(( $ELAPSED + 1 ))
   echo -en "\rruning idle blockchain for $IDLE_TIME seconds $(( $ELAPSED ))%..."
done

cleos get info

PROD_NAME=$(producer_name 1)
   cleos --url http://127.0.0.1:8892/ get table $PROD_NAME $PROD_NAME numobjs
   cleos --url http://127.0.0.1:8892/ get table $PROD_NAME $PROD_NAME hashobjs

pkill nodeos

echo "forks:"
grep "fork or replay" ./nodeos*
echo "errors:"
grep "error" ./nodeos* | grep -v "connection failed" | grep -v "Closing connection"