#!/bin/bash

pushd "$(dirname "$(dirname "${0}")")" > /dev/null || { echo "$0: failed to switch to app directory"; exit 1; }

HRL=src/teletype_default_modules.hrl
STARTED=0

if [ "${1}" = "--rebar" ]; then
    if [ -f "${HRL}" ]; then
        exit 0
    fi
fi

echo "-ifndef(TELETYPE_DEFAULT_MODULES)." > $HRL

for TEMPLATE in $(find src/templates/ -name '*.erl' | sort); do
    FILENAME="$(basename "${TEMPLATE}")"
    MODULE=${FILENAME%.erl}
    [[ $MODULE = 'teletype_template_skel' ]] && continue
    if [[ 0 -eq $STARTED ]]; then
        echo "-define(DEFAULT_MODULES, ['$MODULE'" >> $HRL
        STARTED=1
    else
        echo "                         ,'$MODULE'" >> $HRL
    fi
done

{
    echo "                         ]).";
    echo "-define(TELETYPE_DEFAULT_MODULES, 'true').";
    echo "-endif.";
} >> $HRL

popd > /dev/null || { echo "$): failed to popd out of app directory"; exit 1; }
