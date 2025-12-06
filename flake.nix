{
    inputs = { } ;
    outputs =
        {
            self
        } :
            {
                lib =
                    { failure , pkgs } :
                        let
                            implementation =
                                {
                                    channel ? "redis" ,
                                    quarantine-directory
                                } :
                                    let
                                        application =
                                            {
                                                name = "resource-resolver" ;
                                                runtimeInputs = [ pkgs.coreutils pkgs.gettext pkgs.redis ] ;
                                                text =
                                                    let
                                                        resolve =
                                                            let
                                                                application =
                                                                    pkgs.writeShellApplication
                                                                        {
                                                                            name = "resolve" ;
                                                                            runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.redis failure ] ;
                                                                            text =
                                                                                ''
                                                                                    ARGUMENTS=( "$@" )
                                                                                    # shellcheck disable=SC2034
                                                                                    ARGUMENTS_JSON="$( printf '%s\n' "${ builtins.concatStringsSep "" [ "$" "{" "ARGUMENTS[@]" "}" ] }" | jq -R . | jq -s . )" || failure 61a8398a
                                                                                    if [[ -t 0 ]]
                                                                                    then
                                                                                        HAS_STANDARD_INPUT=false
                                                                                        STANDARD_INPUT=""
                                                                                    else
                                                                                        HAS_STANDARD_INPUT=true
                                                                                        STANDARD_INPUT="$( cat )" || failure b78f1b75
                                                                                    fi
                                                                                    export HAS_STANDARD_INPUT
                                                                                    export STANDARD_INPUT
                                                                                    export RELEASE
                                                                                    JSON="$(
                                                                                        jq \
                                                                                            --null-input \
                                                                                            --compact-output \
                                                                                            --argjson ARGUMENTS "$ARGUMENTS_JSON" \
                                                                                            --arg HAS_STANDARD_INPUT "$HAS_STANDARD_INPUT" \
                                                                                            --argjson RELEASE_RESOLUTIONS '$RELEASE_RESOLUTIONS_JSON' \
                                                                                            --arg STANDARD_INPUT "$STANDARD_INPUT" \
                                                                                            '
                                                                                                {
                                                                                                    "arguments" : $ARGUMENTS ,
                                                                                                    "has-standard-input" : ( $HAS_STANDARD_INPUT | test("true") ) ,
                                                                                                    "index" : "$INDEX" ,
                                                                                                    "mode" : ( "$MODE" | test("true") ) ,
                                                                                                    "release" : "$RELEASE" ,
                                                                                                    "release-resolutions" : $RELEASE_RESOLUTIONS ,
                                                                                                    "resolution" : "$RESOLUTION" ,
                                                                                                    "standard-input" : $STANDARD_INPUT ,
                                                                                                    "type" : "$TYPE"
                                                                                                }
                                                                                            '
                                                                                    )" || failure 7a875425
                                                                                    redis-cli PUBLISH ${ config.personal.channel } "$JSON" > /dev/null
                                                                                    yq eval --prettyPrint "." - <<< "$JSON"
                                                                                    rm --force "${ quarantine-directory }/$INDEX/init/resolve.sh"
                                                                                    rm --recursive --force "${ quarantine-directory }/$INDEX/init/resolve"
                                                                                '' ;
                                                                        } ;
                                                            in "${ application }/bin/resolve" ;
                                                        in
                                                            ''
                                                                redis-cli SUBSCRIBE ${ channel } | while true
                                                                do
                                                                    read -r TYPE || failure 76c840d6
                                                                    read -r CHANNEL || failure 0702dae0
                                                                    read -r PAYLOAD || failure 3280f3d7
                                                                    if [[ "$TYPE" == "message" ]] && [[ "${ channel }" == "$CHANNEL" ]]
                                                                    then
                                                                        TYPE_="$( jq --raw-output ".type" - <<< "$PAYLOAD" )" || failure 1dc13b8d
                                                                        if [[ "invalid" == "$TYPE_" ]]
                                                                        then
                                                                            INDEX="$( yq eval ".index | tostring " - <<< "$PAYLOAD" )" || failure 45ac1a52
                                                                            mkdir --parents "${ quarantine-directory }/$INDEX/init"
                                                                            export ARGUMENTS="\$ARGUMENTS"
                                                                            export ARGUMENTS_JSON="\$ARGUMENTS_JSON"
                                                                            export INDEX
                                                                            export JSON="\$JSON"
                                                                            export HAS_STANDARD_INPUT="\$HAS_STANDARD_INPUT"
                                                                            RELEASE="$( yq eval ".description.secondary.seed.release" - <<< "$PAYLOAD" )" || failure 8cdca9f1
                                                                            export RELEASE
                                                                            export RELEASE_RESOLUTIONS="\$RELEASE_RESOLUTIONS"
                                                                            RELEASE_RESOLUTIONS_JSON="$( yq eval --output-format=json '.description.secondary.seed.resolutions.release // []' - <<< "$PAYLOAD" )" || failure f7cbb413
                                                                            export RELEASE_RESOLUTIONS_JSON
                                                                            export STANDARD_INPUT="\$STANDARD_INPUT"
                                                                            export TYPE="resolve-init"
                                                                            yq eval --prettyPrint '.' - <<< "$PAYLOAD" > "${ quarantine-directory }/$INDEX/init.yaml"
                                                                            chmod 0400 "${ quarantine-directory }/$INDEX/init.yaml"
                                                                            MODE=false RESOLUTION=init envsubst < "${ resolve }" > "${ quarantine-directory }/$INDEX/init.sh"
                                                                            chmod 0500 "${ quarantine-directory }/$INDEX/init.sh"
                                                                            yq eval '.description.secondary.seed.resolutions.init // [] | .[]' - <<< "$PAYLOAD" | while IFS= read -r RESOLUTION
                                                                            do
                                                                                export MODE=true
                                                                                export RESOLUTION
                                                                                envsubst < "${ resolve }" > "${ quarantine-directory }/$INDEX/init/$RESOLUTION"
                                                                                chmod 0500 "${ quarantine-directory }/$INDEX/init/$RESOLUTION"
                                                                            done
                                                                        fi
                                                                    fi
                                                                done
                                                            '' ;
                                            } ;
                                        in "${ application }/bin/resource-resolver" ;
                            in
                                {
                                    check =
                                        {
                                            channel ? "eff208cc" ,
                                            expected ,
                                            quarantine-directory ? "b5f8cc19"
                                        } :
                                            pkgs.stdenv.mkDerivation
                                                {
                                                    installPhase = ''execute-test "$out"'' ;
                                                    name = "check" ;
                                                    nativeBuildInputs =
                                                        [
                                                            (
                                                                let
                                                                    observed = builtins.toString ( implementation { channel = channel ; quarantine-directory = quarantine-directory ; } ) ;
                                                                    in
                                                                        if expected == observed then
                                                                            pkgs.writeShellApplication
                                                                                {
                                                                                    name = "execute-test" ;
                                                                                    runtimeInputs = [ pkgs.coreutils ] ;
                                                                                    text =
                                                                                        ''
                                                                                            OUT="$1"
                                                                                            touch "$OUT"
                                                                                        '' ;
                                                                                }
                                                                        else
                                                                            pkgs.writeShellApplication
                                                                                {
                                                                                    name = "execute-test" ;
                                                                                    runtimeInputs = [ pkgs.coreutils failure ] ;
                                                                                    text =
                                                                                        ''
                                                                                            OUT="$1"
                                                                                            touch "$OUT"
                                                                                            failure 33c629b1 "We were expecting ${ expected } but we observed ${ observed }"
                                                                                        '' ;
                                                                                }
                                                            )
                                                        ] ;
                                                    src = ./. ;
                                                } ;
                                    implementation = implementation ;
                                } ;
            } ;
}