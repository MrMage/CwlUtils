//
//  CwlUnanticipatedError.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2015/03/05.
//  Copyright © 2015 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.
//
//  Permission to use, copy, modify, and/or distribute this software for any
//  purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
//  SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
//  IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//

#if os(OSX)
import Cocoa
#elseif os(iOS)
import UIKit
import MobileCoreServices
#endif

public extension ErrorType {
	/// Return an NSError with the same properties as this error but with an `UnanticipatedErrorRecoveryAttempter` attached.
	public func withUnanticipatedErrorRecoveryAttempter(file file: String = #file, line: Int = #line) -> NSError {
		// We want to preserve the "userInfo" dictionary, so we avoid "self as NSError" if we can (since it creates a new NSError that doesn't preserve the userInfo). Instead, we cast *via* NSObject.
		let e = ((self as? NSObject) as? NSError) ?? (self as NSError)
		var userInfo: [NSObject: AnyObject] = e.userInfo
		
		if userInfo[NSLocalizedDescriptionKey] == nil, let description = (self as? CustomStringConvertible)?.description {
			userInfo[NSLocalizedDescriptionKey] = description
		}
		
		// Move any existing NSLocalizedRecoverySuggestionErrorKey to a new key (we want to replace it but don't want to lose potentially useful information)
		if let previousSuggestion = userInfo[NSLocalizedRecoverySuggestionErrorKey] {
			userInfo[UnanticipatedErrorRecoveryAttempter.PreviousRecoverySuggestionKey] = previousSuggestion
		}
		
		// Attach a new NSLocalizedRecoverySuggestionErrorKey and our recovery attempter and options
		let directory = ((file as NSString).stringByDeletingLastPathComponent as NSString).lastPathComponent
		let filename = (file as NSString).lastPathComponent
		let suggestion = NSString(format: NSLocalizedString("The error occurred at line %ld of the %@/%@ file in the program's code.",  comment: ""), line, directory, filename)
		userInfo[NSLocalizedRecoverySuggestionErrorKey] = suggestion
		userInfo[NSLocalizedRecoveryOptionsErrorKey] = UnanticipatedErrorRecoveryAttempter.localizedRecoveryOptions()
		userInfo[NSRecoveryAttempterErrorKey] = UnanticipatedErrorRecoveryAttempter()

		// Attach the call stack
		userInfo[UnanticipatedErrorRecoveryAttempter.ReturnAddressesKey] = callStackReturnAddresses()

		return NSError(domain: e.domain, code: e.code, userInfo: userInfo)
	}
}

/// A convenience wrapper that applies `withUnanticipatedErrorRecoveryAttempter` to any error thrown by the wrapped function
public func rethrowUnanticipated<T>(file file: String = #file, line: Int = #line, @noescape f: () throws -> T) throws -> T {
    do {
        return try f()
    } catch {
        throw error.withUnanticipatedErrorRecoveryAttempter(file: file, line: line)
    }
}

public func rethrowUnanticipated<T>(file file: String = #file, line: Int = #line, @autoclosure _ f: () throws -> T) throws -> T {
    do {
        return try f()
    } catch {
        throw error.withUnanticipatedErrorRecoveryAttempter(file: file, line: line)
    }
}

/// Class usable as the NSRecoveryAttempterErrorKey object in an NSError that presents the 'Unexpected' error and gives the option of copying the full error to the pasteboard.
public class UnanticipatedErrorRecoveryAttempter: NSObject {
	/// Key used in NSError.userInfo dictionaries to store call stack addresses
	public static let ReturnAddressesKey = "CwlUtils.CallStackReturnAddresses"

	/// Key used in NSError.userInfo dictionaries to store an OnDelete object that raises a fatal error if not cancelled
	public static let PreviousRecoverySuggestionKey = "CwlUtils.PreviousRecoverySuggestion"

	/// Present two buttons: "Copy details" and "OK"
	private class func localizedRecoveryOptions() -> [String] {
		return [NSLocalizedString("OK", comment:""), NSLocalizedString("Copy details", comment:"")]
	}
	
	/// There are two possible `attemptRecoveryFromError` methods. This one just feeds into the other.
	public override func attemptRecoveryFromError(error: NSError, optionIndex: Int, delegate: AnyObject?, didRecoverSelector: Selector, contextInfo: UnsafeMutablePointer<Void>) -> Void {
		self.attemptRecoveryFromError(error, optionIndex: optionIndex)
	}
	
	/// Generate the "detailed" information for the pasteboard (the error dialog itself will show the brief details)
	private func extendedErrorInformation(error: NSError) -> String {
		var userInfo = error.userInfo
		
		// Fetch and format diagnostic information for display
		let callStackSymbols = (userInfo[UnanticipatedErrorRecoveryAttempter.ReturnAddressesKey] as? [UInt]).map { symbolsForCallStackAddresses($0).joinWithSeparator("\n") } ?? NSLocalizedString("(Call stack unavailable)",  comment: "")
		let localizedDescription = error.localizedDescription
		let localizedRecoverySuggestion = error.localizedRecoverySuggestion ?? ""
		let applicationName = (NSBundle.mainBundle().infoDictionary?[kCFBundleNameKey as String] as? String) ?? NSProcessInfo.processInfo().processName
		let applicationVersion = (NSBundle.mainBundle().infoDictionary?[kCFBundleVersionKey as String] as? String) ?? NSLocalizedString("(App version unavailable)",  comment: "")
		let locales = NSLocale.preferredLanguages().joinWithSeparator(", ")
		let machineInfo = "\(Sysctl.machine)/\(Sysctl.model), \(NSProcessInfo.processInfo().operatingSystemVersionString)"
		
		// Remove already handled keys from the userInfo. Anything not yet handled will be output as part of the diagnostic information.
		userInfo.removeValueForKey(NSLocalizedRecoverySuggestionErrorKey)
		userInfo.removeValueForKey(NSLocalizedRecoveryOptionsErrorKey)
		userInfo.removeValueForKey(NSRecoveryAttempterErrorKey)
		userInfo.removeValueForKey(UnanticipatedErrorRecoveryAttempter.PreviousRecoverySuggestionKey)
		userInfo.removeValueForKey(UnanticipatedErrorRecoveryAttempter.ReturnAddressesKey)
		
		return "\(applicationName)/\(applicationVersion), \(machineInfo), \(locales)\n\n\(localizedDescription)\n\(localizedRecoverySuggestion)\n\n\(error.domain): \(error.code). \(userInfo)\n\n\(callStackSymbols)"
	}
	
	/// When a button is tapped, either close the dialog or copy the error details as appropriate.
	public override func attemptRecoveryFromError(error: NSError, optionIndex: Int) -> Bool {
		// The "Copy details" button is index 1 in the buttons array.
		let copyDetailsButtonIndex = 1
		
		switch optionIndex {
		case copyDetailsButtonIndex:
		#if os(OSX)
			NSPasteboard.generalPasteboard().clearContents()
			NSPasteboard.generalPasteboard().setString(extendedErrorInformation(error), forType:NSPasteboardTypeString)
		#elseif os(iOS)
			UIPasteboard.generalPasteboard().string = extendedErrorInformation(error)
		#endif
			return true
		default:
			return false;
		}
	}
}

#if os(iOS)

/// A protocol to provide functionality similar to NSResponder.presentError on Mac OS X.
public protocol ErrorPresenter {
	func presentError(error: NSError, _ completion: (() -> Void)?)
}

// Implement the ErrorPresent on UIViewController rather than UIResponder since presenting a `UIAlertController` requires a parent `UIViewController`
extension UIViewController: ErrorPresenter {
	/// An adapter function that allows the UnanticipatedErrorRecoveryAttempter to be used on iOS to present errors over a UIViewController.
	public func presentError(error: NSError, _ completion: (() -> Void)? = nil) {
		let alert = UIAlertController(title: error.localizedDescription, message: error.localizedRecoverySuggestion ?? error.localizedFailureReason, preferredStyle: UIAlertControllerStyle.Alert)

		if let ro = error.localizedRecoveryOptions, ra = error.recoveryAttempter as? UnanticipatedErrorRecoveryAttempter {
			for (index, option) in ro.enumerate() {
				alert.addAction(UIAlertAction(title: option, style: UIAlertActionStyle.Default, handler: { (action: UIAlertAction?) -> Void in
					ra.attemptRecoveryFromError(error, optionIndex: index)
				}))
			}
		}
		self.presentViewController(alert, animated: true, completion: completion)
	}
}

#endif
