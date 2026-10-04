#!/usr/bin/env bash
set -euo pipefail

# Deterministic, presentation-only walkthrough; no sockets or encryption are used.
DEMO_DELAY="${DEMO_DELAY:-0}"

if [[ ! "$DEMO_DELAY" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf 'DEMO_DELAY must be a non-negative number of seconds.\n' >&2
    exit 2
fi

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    CYAN=$'\033[36m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RESET=$'\033[0m'
else
    BOLD=''
    DIM=''
    CYAN=''
    GREEN=''
    YELLOW=''
    RESET=''
fi

pause() {
    if [[ "$DEMO_DELAY" != "0" && "$DEMO_DELAY" != "0.0" ]]; then
        sleep "$DEMO_DELAY"
    fi
}

heading() {
    printf '\n%s%s%s\n' "$BOLD$CYAN" "$1" "$RESET"
    printf '%s\n' '------------------------------------------------------------'
    pause
}

log() {
    printf '%s[%s]%s %s\n' "$DIM" "$1" "$RESET" "$2"
    pause
}

message() {
    printf '    %s-->%s %s\n' "$YELLOW" "$RESET" "$1"
    pause
}

printf '%sNeedham-Schroeder (symmetric-key) — end-to-end demo%s\n' "$BOLD" "$RESET"
printf '%sDETERMINISTIC SIMULATION ONLY: no network traffic or real encryption.%s\n' "$DIM" "$RESET"
printf 'Actors: Alice (A), Bob (B), and the Key Distribution Center (KDC)\n'
pause

heading '0. Start the KDC and connect both clients'
log KDC 'Listening at 127.0.0.1:5000'
log Bob 'Connected to KDC; assigned ID 00000001'
log Alice 'Connected to KDC; assigned ID 00000002'
log Bob 'Waiting for Alice on the peer channel (127.0.0.1:5010)'

heading '1. Establish each client-to-KDC key with Diffie-Hellman'
log KDC 'Public parameters: p = 23, g = 5'
log Alice 'KDC public value = 8; Alice public value = 17'
log Alice 'Shared KDC key K_A = 12 (binary 0000001100)'
log Bob 'KDC public value = 4; Bob public value = 11'
log Bob 'Shared KDC key K_B = 13 (binary 0000001101)'
log KDC 'Derived the same per-client keys; values are exposed here for teaching'

heading '2. Alice asks the KDC for a session with Bob'
log Alice 'Wants to talk to Bob (ID 00000001); chooses nonce N1 = 0011010110'
message 'Alice -> KDC: ID_A || ID_B || N1'
log KDC 'Request received: 00000002 || 00000001 || 0011010110'

heading '3. KDC creates a session key and Bob ticket'
log KDC 'Creates session key K_S = 1011001101 and freshness value T = 0110100101'
log KDC 'Bob ticket = E_KB[K_S || ID_A || T]'
log KDC 'Response for Alice = E_KA[K_S || ID_B || T || Bob ticket]'
message 'KDC -> Alice: E_KA[K_S || ID_B || T || E_KB[K_S || ID_A || T]]'
log Alice 'Decrypts the response with K_A; learns K_S and receives Bob ticket'

heading '4. Alice forwards Bob’s ticket'
message 'Alice -> Bob: E_KB[K_S || ID_A || T]'
log Bob 'Decrypts ticket with K_B; learns K_S and Alice ID 00000002'

heading '5. Bob proves possession of the session key'
log Bob 'Chooses challenge nonce N_B = 1110001010'
message 'Bob -> Alice: E_KS[N_B]'
log Alice 'Decrypts challenge and computes N_B - 1 = 1110001001'
message 'Alice -> Bob: E_KS[N_B - 1]'
log Bob 'Decrypts response; expected value received'
printf '\n%s%sSUCCESS:%s Alice and Bob are authenticated and share K_S.\n' "$BOLD" "$GREEN" "$RESET"

heading '6. Example secure-chat exchange'
log Alice 'Types: Hello Bob!'
message 'Alice -> Bob: E_KS["Hello Bob!"]'
log Bob 'Decrypts with K_S: Hello Bob!'
log Bob 'Types: Hi Alice!'
message 'Bob -> Alice: E_KS["Hi Alice!"]'
log Alice 'Decrypts with K_S: Hi Alice!'

printf '\n%s%sDemo complete.%s Ciphertexts above are protocol notation, not computed DES output.\n' "$BOLD" "$GREEN" "$RESET"
printf 'Run with DEMO_DELAY=0.25 bash demo.sh to animate the transcript.\n'
