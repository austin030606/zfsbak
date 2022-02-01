#!/bin/sh
if ! [ $(whoami) = root ]; then
    echo "zfsbak must be run as root" 
    exit 1
fi

Usage() {
    echo "Usage:"
    echo "- create: zfsbak DATASET [ROTATION_CNT]"
    echo "- list: zfsbak -l|--list [DATASET|ID|DATASET ID]"
    echo "- delete: zfsbak -d|--delete [DATASET|ID|DATASET ID]"
    echo "- export: zfsbak -e|--export DATASET [ID]"
    echo "- import: zfsbak -i|--import FILENAME DATASET"
}

List() {
    local list=$(zfs list -rt snapshot -s creation mypool)
    list=$(echo "$list" | awk 'BEGIN{
        id = 0;
        FS = "@";
    }
    {
        if (id == 0) {
            printf("ID\tDATASET\t\tTIME\n");
        } else {
            dataset = $1;
            time = substr($2, 1, 19);
            printf("%d\t%s\t%s\n", id, dataset, time);
        }
        id++;
    }')
    if ! [ "$1" = "" ] ; then
        if [ "$2" = "" ] ; then
            if [ "$1" = "mypool/public" -o "$1" = "mypool/upload" -o "$1" = "mypool/hidden" ] ; then
                list=$(echo "$list" | grep "$1")
                list=$(echo "$list" | awk 'BEGIN{
                    printf("ID\tDATASET\t\tTIME\n");
                    id = 1;
                }
                ($0 != ""){
                    printf("%d\t%s\t%s\n", id, $2, $3);
                    id++;
                }')
            else
                list=$(echo "$list" | awk -v ID="$1" 'BEGIN{
                    printf("ID\tDATASET\t\tTIME\n");
                }
                {
                    if ($1 == ID) {
                        printf("%s\t%s\t%s\n", $1, $2, $3);
                    }
                }')
            fi
        else
            list=$(echo "$list" | grep "$1")
            list=$(echo "$list" | awk 'BEGIN{
                printf("ID\tDATASET\t\tTIME\n");
                id = 1;
            }
            {
                printf("%d\t%s\t%s\n", id, $2, $3);
                id++;
            }')
            list=$( echo "$list" | awk -v ID="$2" 'BEGIN{
                printf("ID\tDATASET\t\tTIME\n");
            }
            {
                if ($1 == ID) {
                    printf("%s\t%s\t%s\n", $1, $2, $3);
                }
            }')

        fi
    fi
    echo "$list"
}

DeleteFiles() {
    if ! [ $# = 0 ] ; then
        for i in "$@" ; do 
            zfs destroy "$i"
            echo "Destroy $i"
        done
    fi
}

Delete() {
    local TMPFILE=$(mktemp tmp.XXXXXX)
    local list=""
    if [ "$#" = 0 ] ; then
        List | grep ":" | awk '{ printf(" %s@%s", $2, $3); }' >> "$TMPFILE"
    else
        if [ "$1" = "mypool/public" -o "$1" = "mypool/upload" -o "$1" = "mypool/hidden" ] ; then
            if [ "$2" = "" ] ; then
                List "$1" | grep "$1" | awk '{ printf(" %s@%s", $2, $3); }' >> "$TMPFILE"
            else
                for i in "$@" ; do 
                    List "$1" | awk -v id="$i" '($1 == id){ printf(" %s@%s", $2, $3); }' >> "$TMPFILE"
                done
            fi
        else
            for i in "$@" ; do 
                List | awk -v id="$i" '($1 == id){ printf(" %s@%s", $2, $3); }' >> "$TMPFILE"
            done
        fi
    fi
    list=$(cat "$TMPFILE")
    if ! [ "$list" = "" ] ; then
        DeleteFiles $list
    fi
    rm "$TMPFILE"
}

Create() {
    local status="make"
    local rstatus="dontroll"
    local rocnt="20"
    local last=$(List "$1" | tail -n 1 | awk '{ printf("%s@%s", $2, $3); }')
    if [ "$#" = 2 ] ; then
        rocnt="$2"
    fi
    if [ "$last" != "DATASET@TIME" ] ; then
        local diff=$(zfs diff "$last")
        if [ "$diff" = "" ] ; then
            echo "Snapshot is the same as latest one!"
            status="dontmake"
        fi
    fi
    if [ "$status" = "make" ] ; then
        zfs snapshot "$1"@`date "+%Y-%m-%d-%H:%M:%S"`
        local snap=$(List "$1" | tail -n 1 | awk '{ printf("%s@%s", $2, $3); }')
        echo "Snap $snap"
    fi
    local cnt=$(List "$1" | grep ":" | grep "" -c)
    if [ "$cnt" -gt "$rocnt" ] ; then
        rstatus="roll"
    fi
    if [ "$rstatus" = "roll" ] ; then
        local listnum=$(echo a | awk -v cnt="$cnt" -v rocnt="$rocnt" '{ 
            num = 0; 
            cnt += 0; 
            rocnt += 0; 
            num = cnt - rocnt; 
            for (i = 0; i < num; i++) { 
                printf("%d ", i + 1); 
            } 
        }')
        Delete $1 $listnum
    fi
}

if [ $# = 0 ] ; then
    Usage
else
    first=$(echo "$*" | awk '{ printf("%s", substr($1, 1, 1)); }')
    if [ "$first" = "-" ] ; then
        while getopts ldei: arg ; do
            case $arg in
                l)
                    List "$2" "$3"
                ;;
                d)
                    args=$(echo "$*" | awk '{ for(i = 2; i <= NF; i++) printf("%s ", $i); }')
                    Delete $args
                ;;
                e)
                    
                ;;
                i)
                    
                ;;
                *)
                    Usage
                ;;
            esac
        done
    else
        Create $@
    fi
fi