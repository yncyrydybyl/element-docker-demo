#!/bin/bash

set -e
set -x

# set up data & secrets dir with the right ownerships in the default location
# to stop docker autocreating them with random owners.
# originally these were checked into the git repo, but that's pretty ugly, so doing it here instead.
mkdir -p data/{element-{web,call},livekit,mas,nginx/{ssl,www,conf.d},postgres,synapse}
mkdir -p secrets/{livekit,postgres,synapse}

# create blank secrets to avoid docker creating empty directories in the host
touch secrets/livekit/livekit_{api,secret}_key \
      secrets/postgres/postgres_password \
      secrets/synapse/signing.key

# grab an env if we don't have one already
if [[ ! -e .env  ]]; then
    cp .env-sample .env

    sed -ir s/^USER_ID=/USER_ID=$(id -u)/ .env
    sed -ir s/^GROUP_ID=/GROUP_ID=$(id -g)/ .env

    read -p "Enter base domain name (e.g. example.com): " DOMAIN
    sed -ir s/^example.com/$DOMAIN/ .env

    # SSL setup
    mkdir -p data/certbot/{conf,www} # stop broken binds
    read -p "Use local mkcert CA for SSL? [y/n] " use_mkcert
    if [[ use_mkcert =~ [Yy] ]]; then
        if [[ ! -x mkcert ]]; then
            echo "Please install mkcert from brew/apt/yum etc"
	    exit
        fi
        mkcert -install
        mkcert $DOMAIN '*.'$DOMAIN
        mkdir -p data/ssl
        mv ${DOMAIN}+1.pem data/ssl/fullchain.pem
        mv ${DOMAIN}+1-key.pem data/ssl/privkey.pem
        cp "$(mkcert -CAROOT)"/rootCA.pem data/ssl/ca-certificates.crt
        # borrow letsencrypt's SSL config
        curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "data/ssl/options-ssl-nginx.conf"
          curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "data/ssl/ssl-dhparams.pem"
    else
        read -p "Use letsencrypt for SSL? [y/n] " use_letsencrypt
        if [[ use_letsencrypt =~ [Yy] ]]; then
	    mkdir -p data/certbot/conf/live/$DOMAIN
	    if [[ ! -L data/ssl ]]; then
                ln -s ../data/certbot/conf/live/$DOMAIN data/ssl
	    fi
            touch data/ssl/ca-certificates.crt # will get overwritten by init-letsencrypt.sh
            exec ./init-letsencrypt.sh
        else
            echo "Please put a valid {privkey,fullchain}.pem and ca-certificates.crt into data/ssl/"
        fi
    fi
else
    echo ".env already exists; move it out of the way first to re-setup"
fi