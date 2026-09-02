# Intentionally empty.
#
# build/make's findleaves stops descending once it finds an Android.mk in a
# directory, so this single file keeps kati out of the entire sm8635-modules
# subtree. Without it, kati parses the vendor DLKM wrappers and dies on
# include paths from other trees:
#   motorola/drivers/*/Android.mk      -> motorola/kernel/modules/AndroidKernelModule.mk
#   qcom/opensource/*/Android.mk       -> device/qcom/common/dlkm/Build_external_kernelmodule.mk
# These modules are built OUT OF TREE by vendor/lineage/build/tasks/kernel.mk
# (TARGET_KERNEL_EXT_MODULES), which invokes each directory's own Makefile.
#
# Mirrors LineageOS/android_kernel_xiaomi_sm8635-modules, whose root Android.mk
# is likewise empty. Note PRODUCT_SOURCE_ROOT_DIRS prunes Android.bp for soong
# but does NOT stop kati -- both mechanisms are needed.
