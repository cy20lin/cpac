#!/bin/sh
##
## Copyright (c) 2017 ChienYu Lin
##
## Author: ChienYu Lin <cy20lin@gmail.com>
## License: MIT
##

dos2unix(){
    sed 's@\r\n@\n@g'
}

load_package_metadata () {
    metadata=$(cat "${default_package_metadata}" \
    | dos2unix \
    | sed '
    /^#.*/ d; # remove comments
    /^.*:$/ s/[^A-Za-z0-9:]//g; # remove special characters
    /^  [^:]*:.*$/ s/: /=/g; # remove special characters
    ' \
    | tr '\n' ';' \
    | sed 's/;  /#!#/g' \
    | tr ';' '\n' \
    | sed 's/:#!#/="/g; s/#!#/;/g; s/$/"/g' \
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
        print "PACKAGE_" $0;
        }
        else {
        }
    }
    END {
        print "PACKAGES=" packages;
    }
   ')
    eval "${metadata}"
}

normalize_name () {
  echo "${name}" | sed 's/[^a-zA-Z0-9]//g' | awk '{ print tolower($0); }'
}

configure_build_install () {
    test -e "${binary_dir}" && rm -rf -- "${binary_dir}" 
    mkdir -p -- "${binary_dir}"
    pushd "${binary_dir}" >/dev/null
    echo "-- [cpac] configuring..." 1>&2
    cmake "${@}" "${source_dir}" || ( popd >/dev/null && return 1 )
    echo "-- [cpac] building..." 1>&2
    cmake --build . || ( popd >/dev/null && return 1 )
    echo "-- [cpac] testing..." 1>&2
    ctest || ( popd >/dev/null && return 1 )
    echo "-- [cpac] installing..." 1>&2
    cmake --build . --target install || ( popd >/dev/null && return 1 )
    popd >/dev/null
    return 0
}

clear_binary_dir() {
    echo "-- [cpac] clearing binary_dir..." 1>&2
    test -e "${binary_dir}" && rm -rf -- "${binary_dir}"

}

retrive_source () {
    echo "-- [cpac] retriving source..." 1>&2
    git clone "${repo}" "${source_dir}" || return 1
    pushd "${source_dir}" >/dev/null 
    case "_${branch}" in
    _) popd >/dev/null && return 0 ;;
    _@)
        branch="tags/$(git describe --abbrev=0 --tags)"
        if test "${branch}" != "tags/" 
        then
            echo "-- [cpac] git checkout '${branch}'" 1>&2
            git checkout "${branch}" || ( popd >/dev/null && return 1 )
        fi
        ;;
    _@*)
        branch=$(echo "${branch}" | sed 's/^.//g')
        echo "-- [cpac] git checkout '${branch}'" 1>&2
        git checkout "${branch}" || ( popd >/dev/null && return 1 )
        ;;
    esac
    popd >/dev/null
    echo done
    return 0
}

clear_source_dir () {
    echo "-- [cpac] clearing source_dir..." 1>&2
    test -e "${source_dir}" && rm -rf -- "${source_dir}"
}

clear_current_package_variables() {
    ARGC=
    name=
    normalized_name=
    repo=
    source_dir=
    binary_dir=
    branch=
}

setup_current_package_variables () {
    clear_current_package_variables
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
                print "spec_type=name;name=\"" $0 "\""
            } else {
                print "spec_type=repo;repo=\"" $0 "\""
            }
          }
        ')
        # echo spec_type=$spec_type
        if test "${spec_type}" == "repo"
        then
            name=$(echo "${ARGV0}" | sed 's@^.*/@@g')
            normalized_name="$(normalize_name)"
        else
            normalized_name="$(normalize_name)"
            ref="PACKAGE_${normalized_name}"
            if eval test "\${${ref}-NOT_FOUND}" == NOT_FOUND
            then
                echo "-- [cpac] package '${name}' metadata not found." 1>&2
                clear_current_package_variables
                return 1
            else
                eval "config=\${${ref}}"
                eval "${config}"
            fi
        fi
        ;;
    2)
        name="$ARGV0"
        repo="$ARGV1"
        normalized_name="$(normalize_name)"
        echo name=$name
        echo repo=$repo
        ;;
    *)
        clear_current_package_variables
        return $(false)
        ;;
    esac
    source_dir="${build_dir}/Source/${name}"
    binary_dir="${build_dir}/Build/${name}"
    branch=$(echo "$1" | sed '/^.*@/ s/^.*\(@.*\)$/\1/g; t end; s/.*//g; :end')
}

show_current_package_variables () {
    echo "-- [cpac] package: $name" 1>&2
    echo "-- [cpac]   name: $name" 1>&2
    echo "-- [cpac]   normalized_name: $normalized_name" 1>&2
    echo "-- [cpac]   repo: $repo" 1>&2
    echo "-- [cpac]   branch: $branch" 1>&2
    echo "-- [cpac]   source_dir: $source_dir" 1>&2
    echo "-- [cpac]   binary_dir: $binary_dir" 1>&2
}

setup_common_variables () {
    this_dir="$(dirname $(readlink -f $0))"
    default_package_metadata="${this_dir}/../etc/cpac.d/packages.yml"
    build_dir="${this_dir}/../var/cache/cpac"
}

do_install () {
    format=$(echo $# | awk '
    {
        if ($0 >= 1) {
          output = "%s";
        }
        for(i = 1; i < $0; ++i) {
          output = output "\\n%s";
        }
        print output;
    }')
    package_spec_list=$(printf "${format}\n" "$@" | awk '
    BEGIN { stop = 0; }
    {
      if (/^--/) { stop = 1; }
      if (/^$/) { next; }
      if (!stop) { print $0; }
    }')
    shift_count=$(printf "${format}\n" "$@" | awk '
    BEGIN { count = 0; }
    {
      if (/^--$/) { print count; exit; }
      else { ++count; }
    }
    END { print count; }
    ')
    # echo sc=$shift_count
    test ! -z "${package_spec_list}" && package_spec_count=$(expr ${package_spec_count} + 1)
    for x in $(seq ${shift_count})
    do
        shift
    done
    printf '%s\n' "${package_spec_list}" | while IFS= read -r spec
    do
        # echo "-- [cpac] with spec=$spec" 1>&2
        setup_current_package_variables "${spec}"
        result=$?
        show_current_package_variables 
        test "$result" \
            && retrive_source \
            && configure_build_install "$@"
        clear_source_dir
        clear_binary_dir
    done
}

show_help_help() {
    cat <<EOF
usage:  cpac <operation> [...]
operations:
    cpac {-h --help}
    cpac {-S --sync} <package(s)> [-- <cmake_configure_option(s)>]

    use 'cpac {-h --help}' with an operation for available options
EOF
}

show_help_sync() {
    cat <<EOF
usage:  cpac {-S --sync} <package(s)> [-- <cmake_configure_option(s)>]
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

show_help () {
    case "$1" in
    -S|--sync) show_help_sync ;;
    -h|--help|*) show_help_help ;;
    esac
}

setup_common_variables
load_package_metadata 
case "$1" in
    -S|--sync)
        shift
        do_install "$@"
        ;;
    -h|--help|*)
        shift
        show_help "$@"
        ;;
esac
