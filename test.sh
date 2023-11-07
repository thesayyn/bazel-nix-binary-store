#!/bin/bash

# Darwin Arm64 at https://cache.nixos.org/wd61sciqs7m6nrrmq6yasrwiijhv1s14.narinfo
# curl -fsSL https://cache.nixos.org/nar/0q8ysphisaikwv2fx0pj2fs76rx3xj12j8p4xxggdyyj81p37xxy.nar.xz | gunzip -d  > 0q8ysphisaikwv2fx0pj2fs76rx3xj12j8p4xxggdyyj81p37xxy.nar.xz

# Linux Arm64 at https://cache.nixos.org/k6i4pbhrgds8cn5b7r1d56yismaj247r.narinfo
# curl -fsSL https://cache.nixos.org/nar/0bgm8giczdqg9mmbpc1slhmsgncvpi1bnn44vv6906y8p6xxzavy.nar.xz | gunzip -d  > 0bgm8giczdqg9mmbpc1slhmsgncvpi1bnn44vv6906y8p6xxzavy.nar.xz
archive="0q8ysphisaikwv2fx0pj2fs76rx3xj12j8p4xxggdyyj81p37xxy.nar.xz"


pad_len=8
pos_file=$(mktemp)
echo 0 > $pos_file


function get_pos() { cat $pos_file; }
function move_pos () { local pos=$(get_pos); echo $((pos + $1)) > $pos_file; } 
function u64 () { od -t u8 -An -v | awk '{print $1}'; }
function assert_eq() { 
    if [[ "$1" != "$2" ]]; then 
        echo "assertion failed($BASH_LINENO): '$1' != '$2'"; 
        exit 1
    fi
}

function read_bytes () {
    local len=$1
    if [[ $len -eq 0 ]]; then
        return 0
    fi
    local end=$((len + 1))
    local pos=$(get_pos)
    move_pos $len
    echo "reading from $pos, $len bytes" >&2
    tail -c +"$((pos+1))" "$archive" | head -c "$len"
}


function read_bytes_padded() {
    local content_len=$(read_bytes $pad_len | u64)
    # echo "content_len $content_len" >&2
    read_bytes $content_len
    local remainder=$((content_len % pad_len))
    if [[ $remainder -gt 0 ]]; then 
        # echo "remainder $header_len $remainder" >&2
        read_bytes $((pad_len - remainder)) > /dev/null
    fi
}

magic="$(read_bytes_padded)"

if [[ $magic != "nix-archive-1" ]]; then 
    echo "wrong nar $magic";
    exit 1
fi


function read_entry () {
    assert_eq "$(read_bytes_padded)" "("
    assert_eq $(read_bytes_padded) "type"
    case "$(read_bytes_padded)" in
        "regular")
            local executable=0
            local tag=$(read_bytes_padded)
            if [[ "$tag" == "executable" ]]; then 
                executable=1;
                read_bytes_padded
                tag=$(read_bytes_padded)
            fi
            assert_eq "$tag" "contents"
            local startpos=$(get_pos)
            startpos=$((startpos+8))
            
            local data=$(mktemp)
            read_bytes_padded > $data

            local len=$(cat $data | wc -c)
            echo "-> pos for "$name" start: $startpos, end: $((startpos+len)), len: $len, $data" 
            assert_eq "$(read_bytes_padded)" ")"
        ;;
        "symlink")
            echo "symlink"
            exit 
        ;;
        "directory")
            while [ true ]; do
                case "$(read_bytes_padded)" in
                    "entry")
                        assert_eq "$(read_bytes_padded)" "("
                        assert_eq "$(read_bytes_padded)" "name"
                        local name=$(read_bytes_padded)
                        assert_eq "$(read_bytes_padded)" "node"
             
                        echo "# reading $name" 
                        read_entry
                        local endpos=$(get_pos)
                        assert_eq "$(read_bytes_padded)" ")"
                    ;;
                    ")")
                        break
                    ;;
                    *)
                        echo "dir"
                        exit 1
                    ;;
                esac
            done           
        ;;
        *)
            echo "default (none of above)"
            exit 1
        ;;
    esac
}

read_entry
