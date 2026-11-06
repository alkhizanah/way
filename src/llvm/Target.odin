/*===-- llvm-c/Target.h - Target Lib C Iface --------------------*- C++ -*-===*/
/*                                                                            */
/* Part of the LLVM Project, under the Apache License v2.0 with LLVM          */
/* Exceptions.                                                                */
/* See https://llvm.org/LICENSE.txt for license information.                  */
/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception                    */
/*                                                                            */
/*===----------------------------------------------------------------------===*/
/*                                                                            */
/* This header declares the C interface to libLLVMTarget.a, which             */
/* implements target information.                                             */
/*                                                                            */
/* Many exotic languages can interoperate with C code but have a harder time  */
/* with C++ due to name mangling. So in addition to C, this interface enables */
/* tools written in such languages.                                           */
/*                                                                            */
/*===----------------------------------------------------------------------===*/
package llvm

foreign import lib "system:LLVM"


/**
* @defgroup LLVMCTarget Target information
* @ingroup LLVMC
*
* @{
*/
ByteOrdering :: enum u32 {
	/**
	* @defgroup LLVMCTarget Target information
	* @ingroup LLVMC
	*
	* @{
	*/
	BigEndian    = 0,

	/**
	* @defgroup LLVMCTarget Target information
	* @ingroup LLVMC
	*
	* @{
	*/
	LittleEndian = 1,
}

TargetDataRef :: ^OpaqueTargetData
OpaqueTargetData :: struct {}
OpaqueTargetLibraryInfotData :: struct {}
TargetLibraryInfoRef :: ^OpaqueTargetLibraryInfotData

@(default_calling_convention = "c", link_prefix = "LLVM")
foreign lib {
	/**
	* Obtain the data layout for a module.
	*
	* @see Module::getDataLayout()
	*/
	GetModuleDataLayout :: proc(M: ModuleRef) -> TargetDataRef ---

	/**
	* Set the data layout for a module.
	*
	* @see Module::setDataLayout()
	*/
	SetModuleDataLayout :: proc(M: ModuleRef, DL: TargetDataRef) ---

	/** Creates target data from a target layout string.
	See the constructor llvm::DataLayout::DataLayout. */
	CreateTargetData :: proc(StringRep: cstring) -> TargetDataRef ---

	/** Deallocates a TargetData.
	See the destructor llvm::DataLayout::~DataLayout. */
	DisposeTargetData :: proc(TD: TargetDataRef) ---

	/** Adds target library information to a pass manager. This does not take
	ownership of the target library info.
	See the method llvm::PassManagerBase::add. */
	AddTargetLibraryInfo :: proc(TLI: TargetLibraryInfoRef, PM: PassManagerRef) ---

	/** Converts target data to a target layout string. The string must be disposed
	with LLVMDisposeMessage.
	See the constructor llvm::DataLayout::DataLayout. */
	CopyStringRepOfTargetData :: proc(TD: TargetDataRef) -> cstring ---

	/** Returns the byte order of a target, either LLVMBigEndian or
	LLVMLittleEndian.
	See the method llvm::DataLayout::isLittleEndian. */
	ByteOrder :: proc(TD: TargetDataRef) -> ByteOrdering ---

	/** Returns the pointer size in bytes for a target.
	See the method llvm::DataLayout::getPointerSize. */
	PointerSize :: proc(TD: TargetDataRef) -> u32 ---

	/** Returns the pointer size in bytes for a target for a specified
	address space.
	See the method llvm::DataLayout::getPointerSize. */
	PointerSizeForAS :: proc(TD: TargetDataRef, AS: u32) -> u32 ---

	/** Returns the integer type that is the same size as a pointer on a target.
	See the method llvm::DataLayout::getIntPtrType. */
	IntPtrType :: proc(TD: TargetDataRef) -> TypeRef ---

	/** Returns the integer type that is the same size as a pointer on a target.
	This version allows the address space to be specified.
	See the method llvm::DataLayout::getIntPtrType. */
	IntPtrTypeForAS :: proc(TD: TargetDataRef, AS: u32) -> TypeRef ---

	/** Returns the integer type that is the same size as a pointer on a target.
	See the method llvm::DataLayout::getIntPtrType. */
	IntPtrTypeInContext :: proc(C: ContextRef, TD: TargetDataRef) -> TypeRef ---

	/** Returns the integer type that is the same size as a pointer on a target.
	This version allows the address space to be specified.
	See the method llvm::DataLayout::getIntPtrType. */
	IntPtrTypeForASInContext :: proc(C: ContextRef, TD: TargetDataRef, AS: u32) -> TypeRef ---

	/** Computes the size of a type in bits for a target.
	See the method llvm::DataLayout::getTypeSizeInBits. */
	SizeOfTypeInBits :: proc(TD: TargetDataRef, Ty: TypeRef) -> u64 ---

	/** Computes the storage size of a type in bytes for a target.
	See the method llvm::DataLayout::getTypeStoreSize. */
	StoreSizeOfType :: proc(TD: TargetDataRef, Ty: TypeRef) -> u64 ---

	/** Computes the ABI size of a type in bytes for a target.
	See the method llvm::DataLayout::getTypeAllocSize. */
	ABISizeOfType :: proc(TD: TargetDataRef, Ty: TypeRef) -> u64 ---

	/** Computes the ABI alignment of a type in bytes for a target.
	See the method llvm::DataLayout::getTypeABISize. */
	ABIAlignmentOfType :: proc(TD: TargetDataRef, Ty: TypeRef) -> u32 ---

	/** Computes the call frame alignment of a type in bytes for a target.
	See the method llvm::DataLayout::getTypeABISize. */
	CallFrameAlignmentOfType :: proc(TD: TargetDataRef, Ty: TypeRef) -> u32 ---

	/** Computes the preferred alignment of a type in bytes for a target.
	See the method llvm::DataLayout::getTypeABISize. */
	PreferredAlignmentOfType :: proc(TD: TargetDataRef, Ty: TypeRef) -> u32 ---

	/** Computes the preferred alignment of a global variable in bytes for a target.
	See the method llvm::DataLayout::getPreferredAlignment. */
	PreferredAlignmentOfGlobal :: proc(TD: TargetDataRef, GlobalVar: ValueRef) -> u32 ---

	/** Computes the structure element that contains the byte offset for a target.
	See the method llvm::StructLayout::getElementContainingOffset. */
	ElementAtOffset :: proc(TD: TargetDataRef, StructTy: TypeRef, Offset: u64) -> u32 ---

	/** Computes the byte offset of the indexed struct element for a target.
	See the method llvm::StructLayout::getElementContainingOffset. */
	OffsetOfElement :: proc(TD: TargetDataRef, StructTy: TypeRef, Element: u32) -> u64 ---
}

InitializeAllTargetInfos :: proc() {
	InitializeAArch64TargetInfo()
	InitializeAMDGPUTargetInfo()
	InitializeARMTargetInfo()
	InitializeAVRTargetInfo()
	InitializeBPFTargetInfo()
	InitializeHexagonTargetInfo()
	InitializeLanaiTargetInfo()
	InitializeLoongArchTargetInfo()
	InitializeMipsTargetInfo()
	InitializeMSP430TargetInfo()
	InitializeNVPTXTargetInfo()
	InitializePowerPCTargetInfo()
	InitializeRISCVTargetInfo()
	InitializeSparcTargetInfo()
	InitializeSPIRVTargetInfo()
	InitializeSystemZTargetInfo()
	InitializeVETargetInfo()
	InitializeWebAssemblyTargetInfo()
	InitializeX86TargetInfo()
	InitializeXCoreTargetInfo()
}

InitializeAllTargets :: proc() {
	InitializeAArch64Target()
	InitializeAMDGPUTarget()
	InitializeARMTarget()
	InitializeAVRTarget()
	InitializeBPFTarget()
	InitializeHexagonTarget()
	InitializeLanaiTarget()
	InitializeLoongArchTarget()
	InitializeMipsTarget()
	InitializeMSP430Target()
	InitializeNVPTXTarget()
	InitializePowerPCTarget()
	InitializeRISCVTarget()
	InitializeSparcTarget()
	InitializeSPIRVTarget()
	InitializeSystemZTarget()
	InitializeVETarget()
	InitializeWebAssemblyTarget()
	InitializeX86Target()
	InitializeXCoreTarget()
}

InitializeAllTargetMCs :: proc() {
	InitializeAArch64TargetMC()
	InitializeAMDGPUTargetMC()
	InitializeARMTargetMC()
	InitializeAVRTargetMC()
	InitializeBPFTargetMC()
	InitializeHexagonTargetMC()
	InitializeLanaiTargetMC()
	InitializeLoongArchTargetMC()
	InitializeMipsTargetMC()
	InitializeMSP430TargetMC()
	InitializeNVPTXTargetMC()
	InitializePowerPCTargetMC()
	InitializeRISCVTargetMC()
	InitializeSparcTargetMC()
	InitializeSPIRVTargetMC()
	InitializeSystemZTargetMC()
	InitializeVETargetMC()
	InitializeWebAssemblyTargetMC()
	InitializeX86TargetMC()
	InitializeXCoreTargetMC()
}

InitializeAllAsmPrinters :: proc() {
	InitializeAArch64AsmPrinter()
	InitializeAMDGPUAsmPrinter()
	InitializeARMAsmPrinter()
	InitializeAVRAsmPrinter()
	InitializeBPFAsmPrinter()
	InitializeHexagonAsmPrinter()
	InitializeLanaiAsmPrinter()
	InitializeLoongArchAsmPrinter()
	InitializeMipsAsmPrinter()
	InitializeMSP430AsmPrinter()
	InitializeNVPTXAsmPrinter()
	InitializePowerPCAsmPrinter()
	InitializeRISCVAsmPrinter()
	InitializeSparcAsmPrinter()
	InitializeSPIRVAsmPrinter()
	InitializeSystemZAsmPrinter()
	InitializeVEAsmPrinter()
	InitializeWebAssemblyAsmPrinter()
	InitializeX86AsmPrinter()
	InitializeXCoreAsmPrinter()
}

InitializeAllAsmParsers :: proc() {
	InitializeAArch64AsmParser()
	InitializeAMDGPUAsmParser()
	InitializeARMAsmParser()
	InitializeAVRAsmParser()
	InitializeBPFAsmParser()
	InitializeHexagonAsmParser()
	InitializeLanaiAsmParser()
	InitializeLoongArchAsmParser()
	InitializeMipsAsmParser()
	InitializeMSP430AsmParser()
	InitializePowerPCAsmParser()
	InitializeRISCVAsmParser()
	InitializeSparcAsmParser()
	InitializeSystemZAsmParser()
	InitializeVEAsmParser()
	InitializeWebAssemblyAsmParser()
	InitializeX86AsmParser()
}

InitializeAllDisassemblers :: proc() {
	InitializeAArch64Disassembler()
	InitializeAMDGPUDisassembler()
	InitializeARMDisassembler()
	InitializeAVRDisassembler()
	InitializeBPFDisassembler()
	InitializeHexagonDisassembler()
	InitializeLanaiDisassembler()
	InitializeLoongArchDisassembler()
	InitializeMipsDisassembler()
	InitializeMSP430Disassembler()
	InitializePowerPCDisassembler()
	InitializeRISCVDisassembler()
	InitializeSparcDisassembler()
	InitializeSystemZDisassembler()
	InitializeVEDisassembler()
	InitializeWebAssemblyDisassembler()
	InitializeX86Disassembler()
	InitializeXCoreDisassembler()
}

@(default_calling_convention = "c", link_prefix = "LLVM")
foreign lib {
	InitializeAArch64TargetInfo :: proc() ---
	InitializeAMDGPUTargetInfo :: proc() ---
	InitializeARMTargetInfo :: proc() ---
	InitializeAVRTargetInfo :: proc() ---
	InitializeBPFTargetInfo :: proc() ---
	InitializeHexagonTargetInfo :: proc() ---
	InitializeLanaiTargetInfo :: proc() ---
	InitializeLoongArchTargetInfo :: proc() ---
	InitializeMipsTargetInfo :: proc() ---
	InitializeMSP430TargetInfo :: proc() ---
	InitializeNVPTXTargetInfo :: proc() ---
	InitializePowerPCTargetInfo :: proc() ---
	InitializeRISCVTargetInfo :: proc() ---
	InitializeSparcTargetInfo :: proc() ---
	InitializeSPIRVTargetInfo :: proc() ---
	InitializeSystemZTargetInfo :: proc() ---
	InitializeVETargetInfo :: proc() ---
	InitializeWebAssemblyTargetInfo :: proc() ---
	InitializeX86TargetInfo :: proc() ---
	InitializeXCoreTargetInfo :: proc() ---
	InitializeAArch64Target :: proc() ---
	InitializeAMDGPUTarget :: proc() ---
	InitializeARMTarget :: proc() ---
	InitializeAVRTarget :: proc() ---
	InitializeBPFTarget :: proc() ---
	InitializeHexagonTarget :: proc() ---
	InitializeLanaiTarget :: proc() ---
	InitializeLoongArchTarget :: proc() ---
	InitializeMipsTarget :: proc() ---
	InitializeMSP430Target :: proc() ---
	InitializeNVPTXTarget :: proc() ---
	InitializePowerPCTarget :: proc() ---
	InitializeRISCVTarget :: proc() ---
	InitializeSparcTarget :: proc() ---
	InitializeSPIRVTarget :: proc() ---
	InitializeSystemZTarget :: proc() ---
	InitializeVETarget :: proc() ---
	InitializeWebAssemblyTarget :: proc() ---
	InitializeX86Target :: proc() ---
	InitializeXCoreTarget :: proc() ---
	InitializeAArch64TargetMC :: proc() ---
	InitializeAMDGPUTargetMC :: proc() ---
	InitializeARMTargetMC :: proc() ---
	InitializeAVRTargetMC :: proc() ---
	InitializeBPFTargetMC :: proc() ---
	InitializeHexagonTargetMC :: proc() ---
	InitializeLanaiTargetMC :: proc() ---
	InitializeLoongArchTargetMC :: proc() ---
	InitializeMipsTargetMC :: proc() ---
	InitializeMSP430TargetMC :: proc() ---
	InitializeNVPTXTargetMC :: proc() ---
	InitializePowerPCTargetMC :: proc() ---
	InitializeRISCVTargetMC :: proc() ---
	InitializeSparcTargetMC :: proc() ---
	InitializeSPIRVTargetMC :: proc() ---
	InitializeSystemZTargetMC :: proc() ---
	InitializeVETargetMC :: proc() ---
	InitializeWebAssemblyTargetMC :: proc() ---
	InitializeX86TargetMC :: proc() ---
	InitializeXCoreTargetMC :: proc() ---
	InitializeAArch64AsmPrinter :: proc() ---
	InitializeAMDGPUAsmPrinter :: proc() ---
	InitializeARMAsmPrinter :: proc() ---
	InitializeAVRAsmPrinter :: proc() ---
	InitializeBPFAsmPrinter :: proc() ---
	InitializeHexagonAsmPrinter :: proc() ---
	InitializeLanaiAsmPrinter :: proc() ---
	InitializeLoongArchAsmPrinter :: proc() ---
	InitializeMipsAsmPrinter :: proc() ---
	InitializeMSP430AsmPrinter :: proc() ---
	InitializeNVPTXAsmPrinter :: proc() ---
	InitializePowerPCAsmPrinter :: proc() ---
	InitializeRISCVAsmPrinter :: proc() ---
	InitializeSparcAsmPrinter :: proc() ---
	InitializeSPIRVAsmPrinter :: proc() ---
	InitializeSystemZAsmPrinter :: proc() ---
	InitializeVEAsmPrinter :: proc() ---
	InitializeWebAssemblyAsmPrinter :: proc() ---
	InitializeX86AsmPrinter :: proc() ---
	InitializeXCoreAsmPrinter :: proc() ---
	InitializeAArch64AsmParser :: proc() ---
	InitializeAMDGPUAsmParser :: proc() ---
	InitializeARMAsmParser :: proc() ---
	InitializeAVRAsmParser :: proc() ---
	InitializeBPFAsmParser :: proc() ---
	InitializeHexagonAsmParser :: proc() ---
	InitializeLanaiAsmParser :: proc() ---
	InitializeLoongArchAsmParser :: proc() ---
	InitializeMipsAsmParser :: proc() ---
	InitializeMSP430AsmParser :: proc() ---
	InitializePowerPCAsmParser :: proc() ---
	InitializeRISCVAsmParser :: proc() ---
	InitializeSparcAsmParser :: proc() ---
	InitializeSystemZAsmParser :: proc() ---
	InitializeVEAsmParser :: proc() ---
	InitializeWebAssemblyAsmParser :: proc() ---
	InitializeX86AsmParser :: proc() ---
	InitializeAArch64Disassembler :: proc() ---
	InitializeAMDGPUDisassembler :: proc() ---
	InitializeARMDisassembler :: proc() ---
	InitializeAVRDisassembler :: proc() ---
	InitializeBPFDisassembler :: proc() ---
	InitializeHexagonDisassembler :: proc() ---
	InitializeLanaiDisassembler :: proc() ---
	InitializeLoongArchDisassembler :: proc() ---
	InitializeMipsDisassembler :: proc() ---
	InitializeMSP430Disassembler :: proc() ---
	InitializePowerPCDisassembler :: proc() ---
	InitializeRISCVDisassembler :: proc() ---
	InitializeSparcDisassembler :: proc() ---
	InitializeSystemZDisassembler :: proc() ---
	InitializeVEDisassembler :: proc() ---
	InitializeWebAssemblyDisassembler :: proc() ---
	InitializeX86Disassembler :: proc() ---
	InitializeXCoreDisassembler :: proc() ---
}

InitializeNativeTarget :: proc() -> Bool {
	when false {} else when ODIN_ARCH == .amd64 {
		InitializeX86TargetInfo()
		InitializeX86Target()
		InitializeX86TargetMC()
		return 0
	} else when ODIN_ARCH == .i386 {
		InitializeX86TargetInfo()
		InitializeX86Target()
		InitializeX86TargetMC()
		return 0
	} else when ODIN_ARCH == .arm64 {
		InitializeAArch64TargetInfo()
		InitializeAArch64Target()
		InitializeAArch64TargetMC()
		return 0
	} else when ODIN_ARCH == .arm32 {
		InitializeARMTargetInfo()
		InitializeARMTarget()
		InitializeARMTargetMC()
		return 0
	} else when ODIN_ARCH == .riscv64 {
		InitializeRISCVTargetInfo()
		InitializeRISCVTarget()
		InitializeRISCVTargetMC()
		return 0
	} else when ODIN_ARCH == .wasm32 {
		InitializeWebAssemblyTargetInfo()
		InitializeWebAssemblyTarget()
		InitializeWebAssemblyTargetMC()
		return 0
	} else when ODIN_ARCH == .wasm64p32 {
		InitializeWebAssemblyTargetInfo()
		InitializeWebAssemblyTarget()
		InitializeWebAssemblyTargetMC()
		return 0
	} else {return 1}
}

InitializeNativeAsmParser :: proc() -> Bool {
	when false {} else when ODIN_ARCH == .amd64 {
		InitializeX86AsmParser()
		return 0
	} else when ODIN_ARCH == .i386 {
		InitializeX86AsmParser()
		return 0
	} else when ODIN_ARCH == .arm64 {
		InitializeAArch64AsmParser()
		return 0
	} else when ODIN_ARCH == .arm32 {
		InitializeARMAsmParser()
		return 0
	} else when ODIN_ARCH == .riscv64 {
		InitializeRISCVAsmParser()
		return 0
	} else when ODIN_ARCH == .wasm32 {
		InitializeWebAssemblyAsmParser()
		return 0
	} else when ODIN_ARCH == .wasm64p32 {
		InitializeWebAssemblyAsmParser()
		return 0
	} else {return 1}
}

InitializeNativeAsmPrinter :: proc() -> Bool {
	when false {} else when ODIN_ARCH == .amd64 {
		InitializeX86AsmPrinter()
		return 0
	} else when ODIN_ARCH == .i386 {
		InitializeX86AsmPrinter()
		return 0
	} else when ODIN_ARCH == .arm64 {
		InitializeAArch64AsmPrinter()
		return 0
	} else when ODIN_ARCH == .arm32 {
		InitializeARMAsmPrinter()
		return 0
	} else when ODIN_ARCH == .riscv64 {
		InitializeRISCVAsmPrinter()
		return 0
	} else when ODIN_ARCH == .wasm32 {
		InitializeWebAssemblyAsmPrinter()
		return 0
	} else when ODIN_ARCH == .wasm64p32 {
		InitializeWebAssemblyAsmPrinter()
		return 0
	} else {return 1}
}

InitializeNativeDisassembler :: proc() -> Bool {
	when false {} else when ODIN_ARCH == .amd64 {
		InitializeX86Disassembler()
		return 0
	} else when ODIN_ARCH == .i386 {
		InitializeX86Disassembler()
		return 0
	} else when ODIN_ARCH == .arm64 {
		InitializeAArch64Disassembler()
		return 0
	} else when ODIN_ARCH == .arm32 {
		InitializeARMDisassembler()
		return 0
	} else when ODIN_ARCH == .riscv64 {
		InitializeRISCVDisassembler()
		return 0
	} else when ODIN_ARCH == .wasm32 {
		InitializeWebAssemblyDisassembler()
		return 0
	} else when ODIN_ARCH == .wasm64p32 {
		InitializeWebAssemblyDisassembler()
		return 0
	} else {return 1}
}
