// swift-tools-version:5.0
import PackageDescription

let package = Package(
	name: "CwlUtils",
   products: [
   	.library(name: "CwlUtils", type: .dynamic, targets: ["CwlUtils"]),
	],
	dependencies: [
		.package(url: "https://github.com/mattgallagher/CwlPreconditionTesting.git", from: "1.2.0"),
	],
	targets: [
		.target(
			name: "CwlUtils",
			dependencies: [
				.target(name: "CwlFrameAddress"),
				.target(name: "ReferenceRandomGenerators")
			]
		),
		.target(name: "CwlFrameAddress"),
		.target(name: "ReferenceRandomGenerators"),
		.testTarget(
			name: "CwlUtilsTests",
			dependencies: [
				.target(name: "CwlUtils"),
				.product(name: "CwlPreconditionTesting")
			]
		),
	]
)
