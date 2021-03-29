# This file is part of U-Boot verified boot support and is intended to be
# inherited from u-boot recipe and from kernel-fitimage.bbclass.
#
# The signature procedure requires the user to generate an RSA key and
# certificate in a directory and to define the following variable:
#
#   UBOOT_SIGN_KEYDIR = "/keys/directory"
#   UBOOT_SIGN_KEYNAME = "dev" # keys name in keydir (eg. "dev.crt", "dev.key")
#   UBOOT_MKIMAGE_DTCOPTS = "-I dts -O dtb -p 2000"
#   UBOOT_SIGN_ENABLE = "1"
#
# As verified boot depends on fitImage generation, following is also required:
#
#   KERNEL_CLASSES ?= " kernel-fitimage "
#   KERNEL_IMAGETYPE ?= "fitImage"
#
# The signature support is limited to the use of CONFIG_OF_SEPARATE in U-Boot.
#
# The tasks sequence is set as below, using DEPLOY_IMAGE_DIR as common place to
# treat the device tree blob:
#
# * u-boot:do_install_append
#   Install UBOOT_DTB_BINARY to datadir, so that kernel can use it for
#   signing, and kernel will deploy UBOOT_DTB_BINARY after signs it.
#
# * virtual/kernel:do_assemble_fitimage
#   Sign the image
#
# * u-boot:do_deploy[postfuncs]
#   Deploy files like UBOOT_DTB_IMAGE, UBOOT_DTB_SYMLINK and others.
#
# For more details on signature process, please refer to U-Boot documentation.

# We need some variables from u-boot-config
inherit uboot-config

# Signature activation.
UBOOT_SIGN_ENABLE ?= "0"

# Default value for deployment filenames.
UBOOT_DTB_IMAGE ?= "u-boot-${MACHINE}-${PV}-${PR}.dtb"
UBOOT_DTB_BINARY ?= "u-boot.dtb"
UBOOT_DTB_SYMLINK ?= "u-boot-${MACHINE}.dtb"
UBOOT_NODTB_IMAGE ?= "u-boot-nodtb-${MACHINE}-${PV}-${PR}.${UBOOT_SUFFIX}"
UBOOT_NODTB_BINARY ?= "u-boot-nodtb.${UBOOT_SUFFIX}"
UBOOT_NODTB_SYMLINK ?= "u-boot-nodtb-${MACHINE}.${UBOOT_SUFFIX}"
UBOOT_ITS_IMAGE ?= "u-boot-${MACHINE}-${PV}-${PR}.its"
UBOOT_ITS ?= "u-boot.its"
UBOOT_ITS_SYMLINK ?= "u-boot-${MACHINE}.its"
SPL_DIR ?= "${@os.path.dirname(d.getVar("SPL_BINARY")) or '.'}"
SPL_DTB_IMAGE ?= "u-boot-spl-${MACHINE}-${PV}-${PR}.dtb"
SPL_DTB_BINARY ?= "u-boot-spl.dtb"
SPL_DTB_SYMLINK ?= "u-boot-spl-${MACHINE}.dtb"
SPL_NODTB_IMAGE ?= "${@os.path.splitext(d.getVar("SPL_BINARYNAME"))[0]}-nodtb-${MACHINE}-${PV}-${PR}${@os.path.splitext(d.getVar("SPL_BINARYNAME"))[1]}"
SPL_NODTB_BINARY ?= "${@os.path.splitext(d.getVar("SPL_BINARYNAME"))[0]}-nodtb${@os.path.splitext(d.getVar("SPL_BINARYNAME"))[1]}"
SPL_NODTB_SYMLINK ?= "${@os.path.splitext(d.getVar("SPL_BINARYNAME"))[0]}-nodtb-${MACHINE}${@os.path.splitext(d.getVar("SPL_BINARYNAME"))[1]}"

# fitImage Hash Algo
FIT_HASH_ALG ?= "sha256"

# fitImage Signature Algo
FIT_SIGN_ALG ?= "rsa2048"

# Generate keys for signing fitImage
FIT_GENERATE_KEYS ?= "0"

# Size of private key in number of bits
FIT_SIGN_NUMBITS ?= "2048"

# args to openssl genrsa (Default is just the public exponent)
FIT_KEY_GENRSA_ARGS ?= "-F4"

# args to openssl req (Default is -batch for non interactive mode and
# -new for new certificate)
FIT_KEY_REQ_ARGS ?= "-batch -new"

# Standard format for public key certificate
FIT_KEY_SIGN_PKCS ?= "-x509"

# Functions in this bbclass is for u-boot only
UBOOT_PN = "${@d.getVar('PREFERRED_PROVIDER_u-boot') or 'u-boot'}"

concat_dtb_helper() {
	if [ -e "${UBOOT_DTB_BINARY}" ]; then
		ln -sf ${UBOOT_DTB_IMAGE} ${DEPLOYDIR}/${UBOOT_DTB_BINARY}
		ln -sf ${UBOOT_DTB_IMAGE} ${DEPLOYDIR}/${UBOOT_DTB_SYMLINK}
	fi

	if [ -f "${UBOOT_NODTB_BINARY}" ]; then
		install ${UBOOT_NODTB_BINARY} ${DEPLOYDIR}/${UBOOT_NODTB_IMAGE}
		ln -sf ${UBOOT_NODTB_IMAGE} ${DEPLOYDIR}/${UBOOT_NODTB_SYMLINK}
		ln -sf ${UBOOT_NODTB_IMAGE} ${DEPLOYDIR}/${UBOOT_NODTB_BINARY}
	fi

	# Concatenate U-Boot w/o DTB & DTB with public key
	# (cf. kernel-fitimage.bbclass for more details)
	deployed_uboot_dtb_binary='${DEPLOY_DIR_IMAGE}/${UBOOT_DTB_IMAGE}'
	if [ "x${UBOOT_SUFFIX}" = "ximg" -o "x${UBOOT_SUFFIX}" = "xrom" ] && \
		[ -e "$deployed_uboot_dtb_binary" ]; then
		oe_runmake EXT_DTB=$deployed_uboot_dtb_binary
		install ${UBOOT_BINARY} ${DEPLOYDIR}/${UBOOT_IMAGE}
	elif [ -e "${DEPLOYDIR}/${UBOOT_NODTB_IMAGE}" -a -e "$deployed_uboot_dtb_binary" ]; then
		cd ${DEPLOYDIR}
		cat ${UBOOT_NODTB_IMAGE} $deployed_uboot_dtb_binary | tee ${B}/${CONFIG_B_PATH}/${UBOOT_BINARY} > ${UBOOT_IMAGE}
	else
		bbwarn "Failure while adding public key to u-boot binary. Verified boot won't be available."
	fi
}

concat_dtb() {
	if [ "${UBOOT_SIGN_ENABLE}" = "1" -a "${PN}" = "${UBOOT_PN}" -a -n "${UBOOT_DTB_BINARY}" ]; then
		mkdir -p ${DEPLOYDIR}
		if [ -n "${UBOOT_CONFIG}" ]; then
			for config in ${UBOOT_MACHINE}; do
				CONFIG_B_PATH="${config}"
				cd ${B}/${config}
				concat_dtb_helper
			done
		else
			CONFIG_B_PATH=""
			cd ${B}
			concat_dtb_helper
		fi
	fi
}

# Install UBOOT_DTB_BINARY to datadir, so that kernel can use it for
# signing, and kernel will deploy UBOOT_DTB_BINARY after signs it.
install_helper() {
	if [ -f "${UBOOT_DTB_BINARY}" ]; then
		install -d ${D}${datadir}
		# UBOOT_DTB_BINARY is a symlink to UBOOT_DTB_IMAGE, so we
		# need both of them.
		install ${UBOOT_DTB_BINARY} ${D}${datadir}/${UBOOT_DTB_IMAGE}
		ln -sf ${UBOOT_DTB_IMAGE} ${D}${datadir}/${UBOOT_DTB_BINARY}
	else
		bbwarn "${UBOOT_DTB_BINARY} not found"
	fi
}

do_install_append() {
	if [ "${UBOOT_SIGN_ENABLE}" = "1" -a "${PN}" = "${UBOOT_PN}" -a -n "${UBOOT_DTB_BINARY}" ]; then
		if [ -n "${UBOOT_CONFIG}" ]; then
			for config in ${UBOOT_MACHINE}; do
				cd ${B}/${config}
				install_helper
			done
		else
			cd ${B}
			install_helper
		fi
	fi
}

do_deploy_prepend_pn-${UBOOT_PN}() {
	if [ "${UBOOT_SIGN_ENABLE}" = "1" -a -n "${UBOOT_DTB_BINARY}" ]; then
		concat_dtb
	fi
}

python () {
    if d.getVar('UBOOT_SIGN_ENABLE') == '1' and d.getVar('PN') == d.getVar('UBOOT_PN') and d.getVar('UBOOT_DTB_BINARY'):
        kernel_pn = d.getVar('PREFERRED_PROVIDER_virtual/kernel')

        # Make "bitbake u-boot -cdeploy" deploys the signed u-boot.dtb
        d.appendVarFlag('do_deploy', 'depends', ' %s:do_deploy' % kernel_pn)
}
