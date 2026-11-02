/**
 * Saves a PDF (base64) to an Account as a Salesforce File (ContentVersion).
 */
public with sharing class de_Contract_Pdf_Service {
  /**
   * Rough guard so very large payloads do not blow Apex heap (LWC sends full base64 string).
   */
  private static final Integer MAX_BASE64_CHARS = 4500000;

  /**
   * @param accountId   Account to attach the file to (FirstPublishLocationId)
   * @param base64Pdf   Raw base64 PDF bytes (no data: prefix required; comma prefix allowed)
   * @param title       File title in Files (optional)
   * @return ContentDocument Id
   */
  @AuraEnabled
  public static Id savePdfToAccount(
    Id accountId,
    String base64Pdf,
    String title
  ) {
    if (accountId == null) {
      throw new AuraHandledException('An Account record Id is required.');
    }
    if (accountId.getSobjectType() != Account.SObjectType) {
      throw new AuraHandledException('Files can only be attached to an Account for this action.');
    }
    if (!Schema.sObjectType.Account.isAccessible()) {
      throw new AuraHandledException('You do not have access to this Account.');
    }
    if (!Schema.sObjectType.ContentVersion.isCreateable()) {
      throw new AuraHandledException('You cannot create files.');
    }
    if (String.isBlank(base64Pdf)) {
      throw new AuraHandledException('No PDF data was provided.');
    }
    if (base64Pdf.length() > MAX_BASE64_CHARS) {
      throw new AuraHandledException('The PDF is too large to upload. Try a shorter document.');
    }

    String normalized = base64Pdf;
    if (normalized.contains(',')) {
      normalized = normalized.substringAfter(',');
    }
    normalized = stripWhitespaceForBase64(normalized);

    Blob fileBody;
    try {
      fileBody = EncodingUtil.base64Decode(normalized);
    } catch (Exception e) {
      throw new AuraHandledException('Invalid PDF data.');
    }
    if (fileBody == null || fileBody.size() == 0) {
      throw new AuraHandledException('Decoded PDF is empty.');
    }

    String safeTitle = String.isBlank(title) ? 'Generated contract' : title.trim();
    String pathName = 'de_contract_' + String.valueOf(System.now().getTime()) + '.pdf';

    ContentVersion cv = new ContentVersion();
    cv.Title = safeTitle.length() > 255 ? safeTitle.substring(0, 255) : safeTitle;
    cv.PathOnClient = pathName;
    cv.VersionData = fileBody;
    cv.FirstPublishLocationId = accountId;
    insert cv;

    ContentVersion inserted = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cv.Id
      LIMIT 1
    ];
    if (inserted.ContentDocumentId == null) {
      throw new AuraHandledException('The file was created but could not be linked.');
    }
    return inserted.ContentDocumentId;
  }

  private static String stripWhitespaceForBase64(String s) {
    if (String.isBlank(s)) {
      return s;
    }
    s = s.replace(' ', '');
    s = s.replace('\n', '');
    s = s.replace('\r', '');
    s = s.replace('\t', '');
    s = s.replace('\f', '');
    return s;
  }
}
