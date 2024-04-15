#!/bin/bash
INSTALLDIR="$HOME/.fgfs/Export/efbapps"

if [ ! -d "$INSTALLDIR" ]; then
    mkdir "$INSTALLDIR" || (
        echo "Could not create directory $INSTALLDIR"
        exit 1
    )
fi
rsync -rv --delete "$(dirname $0)/chartfox/" "$HOME/.fgfs/Export/efbapps/chartfox/" --exclude='.*'
