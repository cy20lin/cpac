#!/bin/sh
##
## Copyright (c) 2017 ChienYu Lin
##
## Author: ChienYu Lin <cy20lin@gmail.com>
## License: MIT
##

cpac_pushd () {
    cpac_dir_stack_top="$(expr ${cpac_dir_stack_top} + 1)"
    eval "cpac_dir_stack_${cpac_dir_stack_top}=\"$PWD\""
    cd "$1"
}

cpac_popd () {
    test -z "${cpac_dir_stack_top}" && return
    test "${cpac_dir_stack_top}" -le 0 && return
    eval "cd \"\${cpac_dir_stack_${cpac_dir_stack_top}}\""
    eval "cpac_dir_stack_${cpac_dir_stack_top}="
    cpac_dir_stack_top="$(expr "${cpac_dir_stack_top}" - 1)"
}

cpac_message () {
    echo "-- [cpac] " "$@" 1>&2
}

cpac_dos2unix () {
    sed 's@\r\n@\n@g'
}

cpac_load_package_metadata () {
    # note: '\x27' => single quote (')
    cpac_metadata=$(cat "$1" \
    | cpac_dos2unix \
    | sed '
    /^#.*/ d; # remove comments
    /^.*:$/ s/[^A-Za-z0-9:]//g; # remove special characters
    /^  [^:]*:.*$/ s/: /=/g; # remove special characters
    ' \
    | tr '\n' ';' \
    | sed 's/;  /#!#cpac_/g' \
    | tr ';' '\n' \
    | sed 's/:#!#/=\x27/g; s/#!#/;/g; s/$/\x27/g' \
    | awk '
    BEGIN {
        FS="=";
        OFS="=";
        i = 0;
        packages="";
    }
    {
        if (/^[A-Za-z][A-Za-z0-9]*=/) {
        package = tolower($1);
        $1 = tolower($1);
        if (i == 0) {
            packages = $1;
            ++i;
        }
        else {
            packages = packages ":" $1;
        }
            print "CPAC_PACKAGE_" $0;
        }
        else {
        }
    }
    END {
        print "CPAC_PACKAGES=\x27" packages "\x27";
    }
   ')
    eval "${cpac_metadata}"
}

cpac_load_default_package_metadata () {
    cpac_load_package_metadata "${CPAC_DEFAULT_PACKAGE_METADATA}"
}

cpac_normalize_name () {
  echo "${cpac_name}" | sed 's/[^a-zA-Z0-9]//g' | awk '{ print tolower($0); }'
}

cpac_configure_build_install () {
    cpac_error=0
    test -e "${cpac_binary_dir}" && rm -rf -- "${cpac_binary_dir}"
    mkdir -p -- "${cpac_binary_dir}"
    cpac_pushd "${cpac_binary_dir}"
    while true
    do
        cpac_message "configuring..."
        cmake ${CPAC_CUSTOM_CONFIGURE_ARGS} "${@}" "${cpac_source_dir}" || cpac_error=1
        test "${cpac_error}" -ne 0 && break
        cpac_message "building..."
        cmake --build . ${CPAC_CUSTOM_BUILD_ARGS} || cpac_error=1
        test "${cpac_error}" -ne 0 && break
        cpac_message "testing..."
        ctest ${CPAC_CUSTOM_TEST_ARGS} || cpac_error=1
        test "${cpac_error}" -ne 0 && break
        cpac_message "installing..."
        cmake --build . --target install ${CPAC_CUSTOM_INSTALL_ARGS} || cpac_error=1
        break
    done
    cpac_popd
    return ${cpac_error}
}

cpac_clear_binary_dir () {
    cpac_message "clearing binary_dir..."
    test -e "${cpac_binary_dir}" && rm -rf -- "${cpac_binary_dir}"

}

cpac_retrive_source () {
    cpac_error=0
    cpac_message "retriving source..."
    git clone "${cpac_repo}" "${cpac_source_dir}" || return 1
    cpac_pushd "${cpac_source_dir}"
    case "_${cpac_branch}" in
    _) cpac_popd && return 0 ;;
    _@)
        cpac_branch="tags/$(git describe --abbrev=0 --tags)"
        if test "${cpac_branch}" != "tags/"
        then
            cpac_message "git checkout '${cpac_branch}'"
            git checkout "${cpac_branch}" || cpac_error=1
        fi
        ;;
    _@*)
        cpac_branch=$(echo "${cpac_branch}" | sed 's/^.//g')
        cpac_message "git checkout '${cpac_branch}'"
        git checkout "${cpac_branch}" || cpac_error=1
        ;;
    esac
    cpac_popd
    return ${cpac_error}
}

cpac_clear_source_dir () {
    cpac_message "clearing source_dir..."
    test -e "${cpac_source_dir}" && rm -rf -- "${cpac_source_dir}"
}

cpac_clear_current_package_variables() {
    ARGC=
    cpac_name=
    cpac_normalized_name=
    cpac_repo=
    cpac_source_dir=
    cpac_binary_dir=
    cpac_branch=
}

cpac_setup_current_package_variables () {
    cpac_clear_current_package_variables
    eval $(echo "$1" \
        | sed '/^.*@/ s/^\(.*\)@.*$/\1/g; t end; s/.*/\0/g; :end' \
        | awk '
        BEGIN {
          FS=",";
        }
        {
          output = "ARGC=" NF;
          output = output ";ARGV=\"" $0 "\"";
          for (i = 1; i <= NF; ++i) {
            output = output ";ARGV" (i-1) "=\"" $i "\""
          }
        }
        END {
          print output;
        }
    ')
    case "${ARGC}" in
    1)
        eval $(echo ${ARGV0} | awk '
          {
            if (/^[a-zA-Z][a-zA-Z0-9_.+\-]*$/) {
                print "cpac_spec_type=name;cpac_name=\"" $0 "\""
            } else {
                print "cpac_spec_type=repo;cpac_repo=\"" $0 "\""
            }
          }
        ')
        if test "${cpac_spec_type}" == "repo"
        then
            cpac_name=$(echo "${ARGV0}" | sed 's@^.*/@@g')
            cpac_normalized_name="$(cpac_normalize_name)"
        else
            cpac_normalized_name="$(cpac_normalize_name)"
            cpac_ref="CPAC_PACKAGE_${cpac_normalized_name}"
            if eval test "\${${cpac_ref}-NOT_FOUND}" == NOT_FOUND
            then
                cpac_message "package '${cpac_name}' metadata not found."
                cpac_clear_current_package_variables
                return 1
            else
                eval "cpac_config=\${${cpac_ref}}"
                eval "${cpac_config}"
            fi
        fi
        ;;
    2)
        cpac_name="$ARGV0"
        cpac_repo="$ARGV1"
        cpac_normalized_name="$(cpac_normalize_name)"
        ;;
    *)
        cpac_clear_current_package_variables
        return $(false)
        ;;
    esac
    cpac_source_dir="${CPAC_BUILD_DIR}/Source/${cpac_name}"
    cpac_binary_dir="${CPAC_BUILD_DIR}/Build/${cpac_name}"
    cpac_branch=$(echo "$1" | sed '/^.*@/ s/^.*\(@.*\)$/\1/g; t end; s/.*//g; :end')
}

cpac_show_current_package_variables () {
    cpac_message "package: $cpac_name"
    cpac_message "  name: $cpac_name"
    cpac_message "  normalized_name: $cpac_normalized_name"
    cpac_message "  repo: $cpac_repo"
    cpac_message "  branch: $cpac_branch"
    cpac_message "  source_dir: $cpac_source_dir"
    cpac_message "  binary_dir: $cpac_binary_dir"
}

cpac_sync () {
    cpac_format=$(echo $# | awk '
    {
        if ($0 >= 1) {
          output = "%s";
        }
        for(i = 1; i < $0; ++i) {
          output = output "\\n%s";
        }
        print output;
    }')
    cpac_package_spec_list=$(printf "${cpac_format}\n" "$@" | awk '
    BEGIN { stop = 0; }
    {
      if (/^--/) { stop = 1; }
      if (/^$/) { next; }
      if (!stop) { print $0; }
    }')
    cpac_shift_count=$(printf "${cpac_format}\n" "$@" | awk '
    BEGIN { count = 0; }
    {
      if (/^--$/) { print count; exit; }
      else { ++count; }
    }
    END { print count; }
    ')
    test ! -z "${cpac_package_spec_list}" && cpac_package_spec_count=$(expr ${cpac_package_spec_count} + 1)
    for x in $(seq ${cpac_shift_count})
    do
        shift
    done
    printf '%s\n' "${cpac_package_spec_list}" | while IFS= read -r cpac_spec
    do
        cpac_setup_current_package_variables "${cpac_spec}"
        cpac_error=$?
        cpac_show_current_package_variables
        test "$cpac_error" \
            && cpac_retrive_source \
            && cpac_configure_build_install "$@"
        cpac_clear_source_dir
        cpac_clear_binary_dir
    done
}

cpac_repo () {
    for cpac_spec in $@
    do
        cpac_setup_current_package_variables "${cpac_spec}" 2>/dev/null
        echo "${cpac_repo}"
    done
}

cpac_download () {
    if test -z "$1"
    then
        cpac_help_download
        return
    fi
    cpac_setup_current_package_variables "$1"
    cpac_error=$?
    test "$2" && cpac_source_dir="$2" || cpac_source_dir="${cpac_name}"
    test "${cpac_error}"  && cpac_retrive_source
}

cpac_show_package_list () {
    echo "${CPAC_PACKAGES}" | tr ':' '\n'
}

cpac_help_help () {
    cat <<EOF
usage:  cpac <operation> [...]
operations:
    cpac {-h --help}
    cpac {-S --sync}  <package(s)> [-- <cmake_configure_option(s)>]
    cpac {--download} <package>    [path]
    cpac {--repo}     <package(s)>
    cpac {--packages}

    use 'cpac {-h --help}' with an operation for available options
EOF
}

cpac_help_sync () {
    cat <<EOF
usage:  cpac {-S --sync} <package(s)> [-- <cmake_configure_option(s)>]
description:
  sync <package(s)>
package:
  package can be specified with following syntax
    <package_name>[,<package_repo>][@[git_branch]]
    <package_repo>[@[git_branch]]
example:
  sync a package name with custom cmake_configure_option(s)
  > cpac -S fmt -- -GNinja -DCMAKE_INSTALL_PREFIX=/usr/local
  sync a repo url
  > cpac -S https://github.com/fmtlib/fmt -- -GNinja -DCMAKE_INSTALL_PREFIX=/usr/local
  sync a package name with tag
  > cpac -S fmt@3.0.0 -- -GNinja -DCMAKE_INSTALL_PREFIX=/usr/local
  sync a package name with branch specified
  > cpac -S https://github.com/fmtlib/fmt@release-3.0 -- -GNinja -DCMAKE_INSTALL_PREFIX=/usr/local
EOF
}

cpac_help_download () {
    cat <<EOF
usage:  cpac {--download} <package> [path]
description:
  download <package> to [path]
EOF
}

cpac_help_repo () {
    cat <<EOF
usage:  cpac {--repo} <package(s)>
description:
  show list of repos specified by <package(s)>
EOF
}

cpac_help_packages () {
    cat <<EOF
usage:  cpac {--packages}
description:
  show list of supported packages
EOF
}

cpac_help () {
    case "$1" in
    -S|--sync) cpac_help_sync ;;
    --download) cpac_help_download ;;
    --repo) cpac_help_repo ;;
    --packages) cpac_help_packages ;;
    -h|--help|*) cpac_help_help ;;
    esac
}

cpac_load_default_init () {
    cpac_load_default_package_metadata
}

cpac_load_init () {
    if test -z "${cpac_load_init_disabled}"
    then
        for cpac_init_file in ~/.cpac.sh ~/.cpac.d/init.sh
        do
            if test -f "${cpac_init_file}"
            then
                source "${cpac_init_file}"
                return 0
            fi
        done
    fi
    cpac_load_default_init
}

cpac_setup_common_variables () {
    CPAC_COMMAND="$(readlink -f $0)"
    cpac_this_dir="$(dirname ${CPAC_COMMAND})"
    cpac_prefix_dir="$(dirname ${cpac_this_dir})"
    CPAC_DEFAULT_PACKAGE_METADATA="${cpac_prefix_dir}/etc/cpac.d/packages.yml"
    CPAC_BUILD_DIR="${cpac_prefix_dir}/var/cache/cpac"
    CPAC_PREFIX_DIR="${cpac_prefix_dir}"
    CPAC_DEFAULT_INIT="${cpac_prefix_dir}/etc/cpac.d/init.sh"
}

cpac_setup_common_variables
cpac_load_init "$@"
case "$1" in
-S|--sync)
    shift
    cpac_sync "$@"
    ;;
--download)
    shift
    cpac_download "$@"
    ;;
--repo)
    shift
    cpac_repo "$@"
    ;;
--packages)
    cpac_show_package_list
    ;;
-h|--help|*)
    test "$#" -gt 0 && shift
    cpac_help "$@"
    ;;
esac
