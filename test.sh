#!/bin/bash -eu

build() {
    local t="${1:?}"
    docker build -t $t .
}

generate_certificate_custom_ca() {
    local cacn="${1:?}"
    local cn="${2:?}"
    local days=365
    openssl genrsa -out ca.key 2048
    openssl req -new -x509 -days $days -key ca.key -subj "/C=US/ST=California/L=San Jose/O=Acme, Inc./CN=$cacn" -out ca.crt
    openssl req -newkey rsa:2048 -nodes -keyout server.key -subj "/C=US/ST=California/L=San Jose/O=Acme, Inc./CN=$cn" -out server.csr
    openssl x509 -req -sha256 -days $days -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt
    rm server.csr ca.srl
    openssl x509 -in server.crt -text -noout
    cat server.crt ca.crt > chain.crt
}

find_cert_cn() {
    local container="${1:?}"
    local cn="${2:?}"
    if docker run --rm \
        --volumes-from $container \
        $TAG \
        trust list | grep -A 2 -B 2 "$cn"; then
        echo "OK: $cn found"
        return 0
    else
        echo "KO: $cn not found"
        return 1
    fi
}

find_java_cacert_cn() {
    local container="${1:?}"
    local cn="${2:?}"
    if docker run --rm \
        --volumes-from $container \
        openjdk:alpine \
        keytool -list -keystore /etc/ssl/certs/java/cacerts -storepass changeit -alias "$cn"; then
        echo "OK: $cn found"
        return 0
    else
        echo "KO: $cn not found"
        return 1
    fi
}

reset_cert_volume() {
    local name="${1:?}"
    docker rm $name || true
    echo "Creating $name container"
    docker create --name $name $TAG
}

add_custom_certificates() {
    local container="${1:?}"
    local certs="${2:?}"
    docker cp ${certs}/ca.crt ${container}:/usr/local/share/ca-certificates/ca.crt
    docker cp ${certs}/server.crt ${container}:/usr/local/share/ca-certificates/server.crt
    docker run --rm \
      --volumes-from $container \
      $TAG ca-update
}

TAG=docker-certificates:for-test
CERT_VOLUME_NAME=docker-certificates-cert
cacn="My Custom CA"
cn="acme.corp"

build $TAG

certs="$(pwd)/tmp/certs"
mkdir -p ${certs}

pushd ${certs}
    echo "Generating custom certificate"
    generate_certificate_custom_ca "$cacn" "$cn"
popd

reset_cert_volume $CERT_VOLUME_NAME
echo "Adding custom certificate"
add_custom_certificates "$CERT_VOLUME_NAME" "$certs"

rm -rf ${certs}

# Assert our certificates are now in the system certs
find_cert_cn "$CERT_VOLUME_NAME" "$cacn"
find_cert_cn "$CERT_VOLUME_NAME" "$cn"
# Assert we can find our certificate in java cacerts
find_java_cacert_cn "$CERT_VOLUME_NAME" "$cn"
