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
                                            pkgs.writeShellApplication
                                                {
                                                    name = "resource-resolver" ;
                                                    runtimeInputs =
                                                        [
                                                            pkgs.coreutils
                                                            pkgs.gettext
                                                            pkgs.jq
                                                            pkgs.redis
                                                            pkgs.yq-go
                                                            (
                                                                pkgs.writeShellApplication
                                                                    {
                                                                        name = "iteration" ;
                                                                        runtimeInputs = [ pkgs.coreutils pkgs.gettext pkgs.yq-go failure ] ;
                                                                        text =
                                                                            let
                                                                                resolve =
                                                                                    let
                                                                                        application =
                                                                                            pkgs.writeShellApplication
                                                                                                {
                                                                                                    name = "resolve" ;
                                                                                                    runtimeInputs =
                                                                                                        [
                                                                                                            pkgs.coreutils
                                                                                                            pkgs.jq
                                                                                                            pkgs.redis
                                                                                                            pkgs.yq-go
                                                                                                            failure
                                                                                                        ] ;
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
                                                                                                            redis-cli PUBLISH ${ channel } "$JSON" > /dev/null
                                                                                                            yq eval --prettyPrint "." - <<< "$JSON"
                                                                                                            rm --force "${ quarantine-directory }/$INDEX/init/resolve.sh"
                                                                                                            rm --recursive --force "${ quarantine-directory }/$INDEX/init/resolve"
                                                                                                        '' ;
                                                                                                } ;
                                                                                    in "${ application }/bin/resolve" ;
                                                                                in
                                                                                    ''
                                                                                        RESOLUTIONS=( )
                                                                                        while [[ "$#" -gt 0 ]]
                                                                                        do
                                                                                            case "$1" in
                                                                                                --index)
                                                                                                    INDEX="$2"
                                                                                                    shift 2
                                                                                                    ;;
                                                                                                --resolution)
                                                                                                    RESOLUTIONS+=( "$2" )
                                                                                                    shift 2
                                                                                                    ;;
                                                                                                --type)
                                                                                                    TYPE="$2"
                                                                                                    if [[ "$TYPE" != "init" ]] && [[ "$TYPE" != "release" ]]
                                                                                                    then
                                                                                                        failure 193f44e0
                                                                                                    fi
                                                                                                    shift 2
                                                                                                    ;;
                                                                                                *)
                                                                                                    failure dd61579e
                                                                                                    shift
                                                                                                    ;;
                                                                                            esac
                                                                                        done
                                                                                        if [[ -z "$INDEX" ]]
                                                                                        then
                                                                                            failure 25b5e484
                                                                                        fi
                                                                                        if [[ -z "$TYPE" ]]
                                                                                        then
                                                                                            failure d789f6bc
                                                                                        fi
                                                                                        mkdir --parents "${ quarantine-directory }/$INDEX/$TYPE"
                                                                                        MODE=false envsubst < ${ resolve } > "${ quarantine-directory }/$INDEX/$TYPE.sh"
                                                                                        chmod 0500 "${ quarantine-directory }/$INDEX/$TYPE.sh"
                                                                                        for RESOLUTION in "${ builtins.concatStringsSep "" [ "$" "{" "RESOLUTIONS[@]" "}" ] }"
                                                                                        do
                                                                                            MODE=true envsubst RESOLUTION=$RESOLUTION < ${ resolve } > "${ quarantine-directory }/$INDEX/$TYPE/$TYPE.sh"
                                                                                            chmod 0500 "${ quarantine-directory }/$INDEX/$TYPE/$TYPE.sh"
                                                                                        done
                                                                                        cat | yq eval --prettyPrint '.' - <<< "$PAYLOAD" > "${ quarantine-directory }/$INDEX/$TYPE.yaml"
                                                                                    '' ;
                                                                    }
                                                            )
                                                            failure
                                                        ] ;
                                                    text =
                                                        let
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
                                                                            if [[ "invalid-init" == "$TYPE_" ]] || [[ "invalid-release" == "$TYPE_" ]]
                                                                            then
                                                                                INDEX="$( yq eval ".index | tostring " - <<< "$PAYLOAD" )" || failure 45ac1a52
                                                                                mapfile -t RESOLUTIONS < <(
                                                                                    yq -r '.description.secondary.seed.resolutions.init // [] | .[]' <<< "$PAYLOAD"
                                                                                )
                                                                                RESOLUTION_ARGS=()
                                                                                for r in "${ builtins.concatStringsSep "" [ "$" "{" "RESOLUTIONS[@]" "}" ] }"
                                                                                do
                                                                                    RESOLUTION_ARGS+=( --resolution "$r" )
                                                                                done
                                                                                echo "$PAYLOAD" | iteration --type "$TYPE_" --index "$INDEX" "${ builtins.concatStringsSep "" [ "$" "{" "RESOLUTION_ARGS[@]" "}" ] }" &
                                                                            else
                                                                                echo "releaser ignores $TYPE_"
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