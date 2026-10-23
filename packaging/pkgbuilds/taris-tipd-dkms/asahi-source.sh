#!/bin/bash
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Puts the driver source of the Asahi Linux kernel a DKMS build is for in the build folder, with
# TarisOS's patches, so the patched driver follows every kernel Asahi releases without a new
# package. DKMS runs it before each build (PRE_BUILD in dkms.conf), in the build folder, as root.
# The kernel release names Asahi's source tag (7.2.12-1-1-ARCH: asahi-7.2.12-1); only the folders
# asahi-source.conf names are fetched from Asahi's repository (a shallow, sparse clone, kept in
# /var/cache/taris-dkms for that tag). A patch the source already has is skipped; one that doesn't
# apply stops the build, and the kernel's own driver stays. Without a network the build stops too:
# `dkms autoinstall` builds it later. The same script is in taris-appledrm-dkms,
# taris-brcmfmac-dkms and taris-tipd-dkms; what each needs is in its asahi-source.conf.
# Usage: asahi-source.sh <kernel release>

set -euo pipefail

kernelver=${1:?kernel release}
build=$PWD
repo=https://github.com/AsahiLinux/linux.git
cache_root=/var/cache/taris-dkms

# paths: the kernel source folders to fetch; base: the folder of those the build folder stands
# for; patches: TarisOS's patches against the kernel tree, in order; notices: the patch, against
# the build folder, that marks the changed files (GPL-2.0 section 2a)
source ./asahi-source.conf

if [[ ! $kernelver =~ ^([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)-[0-9]+-ARCH$ ]]; then
  echo "asahi-source: $kernelver isn't a release of Asahi Linux's kernel" >&2
  exit 1
fi
tag=asahi-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}
cache=$cache_root/$tag

if [[ ! -d $cache/.git ]]; then
  mkdir -p "$cache_root"
  rm -rf "$cache.new"
  if ! git -c advice.detachedHead=false clone -q --depth 1 --filter=blob:none --sparse \
    --branch "$tag" "$repo" "$cache.new"; then
    rm -rf "$cache.new"
    echo "asahi-source: $tag couldn't be fetched from $repo" >&2
    exit 1
  fi
  mv "$cache.new" "$cache"
fi
if ! git -C "$cache" sparse-checkout add "${paths[@]}"; then
  echo "asahi-source: ${paths[*]} couldn't be fetched for $tag" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for path in "${paths[@]}"; do
  if [[ ! -d $cache/$path ]]; then
    echo "asahi-source: $tag has no $path" >&2
    exit 1
  fi
  mkdir -p "$work/$(dirname "$path")"
  cp -a "$cache/$path" "$work/$path"
done

for patch in "${patches[@]}"; do
  if patch -d "$work" -p1 -R -f -s --dry-run <"$build/$patch" >/dev/null 2>&1; then
    echo "asahi-source: $tag already has $patch"
  elif patch -d "$work" -p1 -N -s --dry-run <"$build/$patch" >/dev/null 2>&1; then
    patch -d "$work" -p1 -N -s <"$build/$patch"
    echo "asahi-source: $patch applied to $tag"
  else
    echo "asahi-source: $patch doesn't apply to $tag: the kernel's own driver stays" >&2
    exit 1
  fi
done

cp -a "$work/$base/." "$build/"
patch -d "$build" -p1 -N -s <"$build/$notices"

# Only the tags of the kernels installed are kept
for old in "$cache_root"/asahi-*; do
  [[ -d $old ]] || continue
  keep=
  for release in /usr/lib/modules/*-ARCH; do
    if [[ $(basename "$release") =~ ^([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)-[0-9]+-ARCH$ &&
      $(basename "$old") == "asahi-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}" ]]; then
      keep=1
    fi
  done
  [[ $keep ]] || rm -rf "$old"
done
