#!/bin/bash -eux

# prepare binary_name/release_tag/release_asset_name
BINARY_NAME=$(basename ${GITHUB_REPOSITORY})
GIT_COMMIT=$(git rev-parse --short ${GITHUB_SHA})
if [ x${INPUT_BINARY_NAME} != x ]; then
  BINARY_NAME=${INPUT_BINARY_NAME}
fi
RELEASE_TAG=$(basename ${GITHUB_REF})
if [ ! -z "${INPUT_RELEASE_TAG}" ]; then
    RELEASE_TAG=${INPUT_RELEASE_TAG}
fi
RELEASE_ASSET_NAME=${BINARY_NAME}-${RELEASE_TAG}-${INPUT_GOOS}-${INPUT_GOARCH}
if [ ! -z "${INPUT_ASSET_NAME}" ]; then
    RELEASE_ASSET_NAME=${INPUT_ASSET_NAME}
fi

# prompt error if non-supported event
if [ ${GITHUB_EVENT_NAME} == 'release' ]; then
    echo "Event: ${GITHUB_EVENT_NAME}"
elif [ ${GITHUB_EVENT_NAME} == 'push' ]; then
    echo "Event: ${GITHUB_EVENT_NAME}"
elif [ ${GITHUB_EVENT_NAME} == 'workflow_dispatch' ]; then
    echo "Event: ${GITHUB_EVENT_NAME}"
else
    echo "Unsupport event: ${GITHUB_EVENT_NAME}!"
    exit 1
fi

# execute pre-command if exist, e.g. `go get -v ./...`
if [ ! -z "${INPUT_PRE_COMMAND}" ]; then
    eval ${INPUT_PRE_COMMAND}
fi

# binary suffix
EXT=''
if [ ${INPUT_GOOS} == 'windows' ]; then
  EXT='.exe'
fi

# qingcloud config
QINGCLOUD_CONFIG_PATH='/tmp/config.yaml'
if [ ${INPUT_QINGCLOUD^^} == 'TRUE' ]; then
  echo "${INPUT_QINGCLOUD_CONFIG}" >${QINGCLOUD_CONFIG_PATH}
fi

# build
BUILD_ARTIFACTS_FOLDER=build-artifacts-$(date +%s)
mkdir -p ${INPUT_PROJECT_PATH}/${BUILD_ARTIFACTS_FOLDER}
cd ${INPUT_PROJECT_PATH}
if [[ "${INPUT_BUILD_COMMAND}" =~ ^make.* ]]; then
    # start with make, assumes using make to build golang binaries, execute it directly
    GOOS=${INPUT_GOOS} GOARCH=${INPUT_GOARCH} eval ${INPUT_BUILD_COMMAND}
    if [ -f "${BINARY_NAME}${EXT}" ]; then
        # assumes the binary will be generated in current dir, copy it for later processes
        cp ${BINARY_NAME}${EXT} ${BUILD_ARTIFACTS_FOLDER}/
    fi
else
    if [ ! -z "${INPUT_LDFLAGS}" ]; then
      GOOS=${INPUT_GOOS} GOARCH=${INPUT_GOARCH} ${INPUT_BUILD_COMMAND} -o ${BUILD_ARTIFACTS_FOLDER}/${BINARY_NAME}${EXT} ${INPUT_BUILD_FLAGS} -ldflags "${INPUT_LDFLAGS}" ${INPUT_SOURCE_FILES}
    else
      GOOS=${INPUT_GOOS} GOARCH=${INPUT_GOARCH} ${INPUT_BUILD_COMMAND} -o ${BUILD_ARTIFACTS_FOLDER}/${BINARY_NAME}${EXT} ${INPUT_BUILD_FLAGS} ${INPUT_SOURCE_FILES}
    fi

fi


# executable compression
if [ ! -z "${INPUT_EXECUTABLE_COMPRESSION}" ]; then
if [[ "${INPUT_EXECUTABLE_COMPRESSION}" =~ ^upx.* ]]; then
    # start with upx, use upx to compress the executable binary
    eval ${INPUT_EXECUTABLE_COMPRESSION} ${BUILD_ARTIFACTS_FOLDER}/${BINARY_NAME}${EXT}
else
    echo "Unsupport executable compression: ${INPUT_EXECUTABLE_COMPRESSION}!"
    exit 1
fi
fi

# prepare extra files
if [ ! -z "${INPUT_EXTRA_FILES}" ]; then
  cd ${GITHUB_WORKSPACE}
  cp -r ${INPUT_EXTRA_FILES} ${INPUT_PROJECT_PATH}/${BUILD_ARTIFACTS_FOLDER}/
  cd ${INPUT_PROJECT_PATH}
fi

cd ${BUILD_ARTIFACTS_FOLDER}
ls -lha

# compress and package binary, then calculate checksum
RELEASE_ASSET_EXT='.tar.gz'
MEDIA_TYPE='application/gzip'
if [ ${INPUT_GOOS} == 'windows' ]; then
RELEASE_ASSET_EXT='.zip'
MEDIA_TYPE='application/zip'
( shopt -s dotglob; zip -vr ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT} * )
else
( shopt -s dotglob; tar cvfz ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT} * )
fi
MD5_SUM=$(md5sum ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT} | cut -d ' ' -f 1)
SHA256_SUM=$(sha256sum ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT} | cut -d ' ' -f 1)

# prefix upload extra params 
GITHUB_ASSETS_UPLOADR_EXTRA_OPTIONS=''
if [ ${INPUT_OVERWRITE^^} == 'TRUE' ]; then
    GITHUB_ASSETS_UPLOADR_EXTRA_OPTIONS="-overwrite"
fi

# update binary and checksum
github-assets-uploader -f ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT} -mediatype ${MEDIA_TYPE} ${GITHUB_ASSETS_UPLOADR_EXTRA_OPTIONS} -repo ${GITHUB_REPOSITORY} -token ${INPUT_GITHUB_TOKEN} -tag ${RELEASE_TAG}

if [ ${INPUT_QINGCLOUD^^} == 'TRUE' ]; then
  # binary and version
  qingcloud qs create-object -b ${INPUT_QINGCLOUD_BUCKET} -k ${BINARY_NAME}/${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT} -F ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT} -t ${MEDIA_TYPE} -f ${QINGCLOUD_CONFIG_PATH}

  qingcloud qs create-object -b ${INPUT_QINGCLOUD_BUCKET} -k ${BINARY_NAME}/VERSION.txt -d "${RELEASE_TAG} - ${GIT_COMMIT}" -t text/plain -f ${QINGCLOUD_CONFIG_PATH}
fi

if [ ${INPUT_MD5SUM^^} == 'TRUE' ]; then
MD5_EXT='.md5'
MD5_MEDIA_TYPE='text/plain'
echo ${MD5_SUM} >${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}${MD5_EXT}
github-assets-uploader -f ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}${MD5_EXT} -mediatype ${MD5_MEDIA_TYPE} ${GITHUB_ASSETS_UPLOADR_EXTRA_OPTIONS} -repo ${GITHUB_REPOSITORY} -token ${INPUT_GITHUB_TOKEN} -tag ${RELEASE_TAG}

if [ ${INPUT_QINGCLOUD^^} == 'TRUE' ]; then
  qingcloud qs create-object -b ${INPUT_QINGCLOUD_BUCKET} -k ${BINARY_NAME}/${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}${MD5_EXT} -F ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}${MD5_EXT} -t ${MD5_MEDIA_TYPE} -f ${QINGCLOUD_CONFIG_PATH}
fi
fi

if [ ${INPUT_SHA256SUM^^} == 'TRUE' ]; then
SHA256_EXT='.sha256'
SHA256_MEDIA_TYPE='text/plain'
echo ${SHA256_SUM} >${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}${SHA256_EXT}
github-assets-uploader -f ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}${SHA256_EXT} -mediatype ${SHA256_MEDIA_TYPE} ${GITHUB_ASSETS_UPLOADR_EXTRA_OPTIONS} -repo ${GITHUB_REPOSITORY} -token ${INPUT_GITHUB_TOKEN} -tag ${RELEASE_TAG}

if [ ${INPUT_QINGCLOUD^^} == 'TRUE' ]; then
  qingcloud qs create-object -b ${INPUT_QINGCLOUD_BUCKET} -k ${BINARY_NAME}/${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}${SHA256_EXT} -F ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}${SHA256_EXT} -t ${SHA256_MEDIA_TYPE} -f ${QINGCLOUD_CONFIG_PATH}
fi

fi

if [ ${INPUT_SIGNIFY^^} == 'TRUE' ]; then
KEY_PATH='/tmp/key.sec'
SHA256_MSG='/tmp/msg'
SIGNIFY_EXT='.sig'
SIGNIFY_MEDIA_TYPE='text/plain'
echo "${INPUT_SIGNIFY_SEC_KEY}" >${KEY_PATH}
echo "SHA256 (${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}) = ${SHA256_SUM}" > ${SHA256_MSG}

if [ -z "${INPUT_SIGNIFY_SEC_KEY_PASS}" ]; then
  signify-openbsd -S -e -s ${KEY_PATH} -m ${SHA256_MSG} -x ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}${SIGNIFY_EXT}
else
  echo "${INPUT_SIGNIFY_SEC_KEY_PASS}" | signify-openbsd -S -e -s ${KEY_PATH} -m ${SHA256_MSG} -x ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}${SIGNIFY_EXT}
fi

rm -rf ${KEY_PATH}
rm -rf ${SHA256_MSG}
github-assets-uploader -f ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}${SIGNIFY_EXT} -mediatype ${SIGNIFY_MEDIA_TYPE} ${GITHUB_ASSETS_UPLOADR_EXTRA_OPTIONS} -repo ${GITHUB_REPOSITORY} -token ${INPUT_GITHUB_TOKEN} -tag ${RELEASE_TAG}

if [ ${INPUT_QINGCLOUD^^} == 'TRUE' ]; then
  qingcloud qs create-object -b ${INPUT_QINGCLOUD_BUCKET} -k ${BINARY_NAME}/${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}${SIGNIFY_EXT} -F ${RELEASE_ASSET_NAME}${RELEASE_ASSET_EXT}${SIGNIFY_EXT} -t ${SIGNIFY_MEDIA_TYPE} -f ${QINGCLOUD_CONFIG_PATH}
fi

fi

rm -rf ${QINGCLOUD_CONFIG_PATH}

