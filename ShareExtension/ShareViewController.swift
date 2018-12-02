//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Lukas Vavrek on 01/12/2018.
//  Copyright © 2018 Lukas Vavrek. All rights reserved.
//

import UIKit
import Social
import CoreServices
import WebKit

class ShareViewController: UIViewController, UIDocumentInteractionControllerDelegate  {
    @IBOutlet weak var webView: WKWebView!
   
    private let plainTextIdentifier = "public.rtf" // public.plain-text
    private var documentInteractionController: UIDocumentInteractionController?
    private var tmp: TemporaryFile?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem else { return }
        
        for attachment in extensionItem.attachments! {
            if attachment.hasItemConformingToTypeIdentifier(plainTextIdentifier) {
                attachment.loadItem(forTypeIdentifier: plainTextIdentifier,
                                    options: nil) { (data, error) in
                    guard let url = data as? URL else { return }
                    
                    guard let attributedString = try? NSAttributedString(
                        url: url,
                        options: [
                            NSAttributedString.DocumentReadingOptionKey.documentType:
                                NSAttributedString.DocumentType.rtf
                        ],
                        documentAttributes: nil) else { return }
                        
                    self.exportToPDF(attributedString: attributedString)
                }
            }
        }
    }

    func exportToPDF(attributedString: NSAttributedString) {
        let pdfData = createPDFwithAttributedString(attributedString)
        
        DispatchQueue.main.sync {
            if tmp != nil {
                return
            }
            
            tmp = try? TemporaryFile(creatingTempDirectoryForFilename: "export.pdf")
            if let tmp = tmp {
                pdfData.write(to: tmp.fileURL, atomically: true)
                
                documentInteractionController = UIDocumentInteractionController(url: tmp.fileURL)
                documentInteractionController?.delegate = self
                documentInteractionController?.presentPreview(animated: true)
            }
        }
    }

    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
    
    func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        documentInteractionController = nil
        try? tmp?.deleteDirectory()
        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }
    
//    https://stackoverflow.com/a/44525201
    func createPDFwithAttributedString(_ currentText: NSAttributedString) -> NSMutableData {
        let pdfData = NSMutableData()
        
        // Create the PDF context using the default page size of 612 x 792.
        UIGraphicsBeginPDFContextToData(pdfData, CGRect.zero, nil)
        
        let framesetter = CTFramesetterCreateWithAttributedString(currentText)
        
        var currentRange = CFRangeMake(0, 0);
        var currentPage = 0;
        var done = false;
        
        repeat {
            // Mark the beginning of a new page.
            UIGraphicsBeginPDFPageWithInfo(CGRect(x: 0, y: 0, width: 612, height: 792), nil);
            
            // Draw a page number at the bottom of each page.
            currentPage += 1;
            
            // Render the current page and update the current range to
            // point to the beginning of the next page.
            renderPagewithTextRange(currentRange: &currentRange, framesetter: framesetter)
            
            // If we're at the end of the text, exit the loop.
            if (currentRange.location == CFAttributedStringGetLength(currentText)){
                done = true;
            }
        } while (!done);
        
        // Close the PDF context and write the contents out.
        UIGraphicsEndPDFContext();
        return pdfData
    }
    
    func renderPagewithTextRange (currentRange: inout CFRange,  framesetter: CTFramesetter) {
        // Get the graphics context.
        if let currentContext = UIGraphicsGetCurrentContext(){
            
            // Put the text matrix into a known state. This ensures
            // that no old scaling factors are left in place.
            currentContext.textMatrix = CGAffineTransform.identity;
            
            // Create a path object to enclose the text. Use 72 point
            // margins all around the text.
            let frameRect = CGRect(x: 72, y: 72, width: 468, height: 648);
            let framePath = CGMutablePath();
            framePath.addRect(frameRect)
            
            // Get the frame that will do the rendering.
            // The currentRange variable specifies only the starting point. The framesetter
            // lays out as much text as will fit into the frame.
            let frameRef = CTFramesetterCreateFrame(framesetter, currentRange, framePath, nil);
            
            // Core Text draws from the bottom-left corner up, so flip
            // the current transform prior to drawing.
            currentContext.translateBy(x: 0, y: 792);
            currentContext.scaleBy(x: 1.0, y: -1.0);
            
            // Draw the frame.
            CTFrameDraw(frameRef, currentContext);
            
            // Update the current range based on what was drawn.
            currentRange = CTFrameGetVisibleStringRange(frameRef);
            currentRange.location += currentRange.length;
            currentRange.length = 0;
        }
    }
}
