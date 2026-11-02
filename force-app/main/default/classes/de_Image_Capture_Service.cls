/**
 * Persists a visiting-card image (or similar) as Salesforce Files (ContentVersion)
 * and returns ContentDocumentId for use in Flows and follow-up automation.
 */
public with sharing class de_Image_Capture_Service {
  /**
   * @param base64        Raw base64 or data URL (comma prefix allowed)
   * @param pathOnClient  File name with extension, e.g. cards.jpg
   * @param title         File title in Files
   * @param recordId      Optional host record (e.g. Visit__c); when null, file is created for the running user
   * @return ContentDocument Id
   */
  @AuraEnabled
  public static Id saveVisitingCardImage(
    String base64,
    String pathOnClient,
    String title,
    Id recordId
  ) {
    if (String.isBlank(base64)) {
      throw new AuraHandledException('No file data to save.');
    }
    if (String.isBlank(pathOnClient)) {
      pathOnClient = 'visiting_cards.jpg';
    }
    if (String.isBlank(title)) {
      title = 'Visiting cards capture';
    }

    String normalized = base64.contains(',')
      ? base64.substringAfter(',')
      : base64;
    normalized = stripWhitespaceForBase64(normalized);

    Blob fileBody;
    try {
      fileBody = EncodingUtil.base64Decode(normalized);
    } catch (Exception e) {
      throw new AuraHandledException('Invalid file data.');
    }
    if (fileBody == null || fileBody.size() == 0) {
      throw new AuraHandledException('The file is empty.');
    }

    ContentVersion cv = new ContentVersion();
    cv.Title = title;
    cv.PathOnClient = pathOnClient;
    cv.VersionData = fileBody;
    if (recordId != null) {
      cv.FirstPublishLocationId = recordId;
    }
    insert cv;

    ContentVersion inserted = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cv.Id
      LIMIT 1
    ];
    if (inserted.ContentDocumentId == null) {
      throw new AuraHandledException('File was created but ContentDocument Id is missing.');
    }
    return inserted.ContentDocumentId;
  }

  public class AccountPickOption {
    @AuraEnabled
    public String value { get; set; }
    @AuraEnabled
    public String label { get; set; }
  }

  /**
   * Lightweight Account name search for Flow-safe pickers (replaces lightning-record-picker on Flow screens).
   */
  @AuraEnabled(cacheable=true)
  public static List<AccountPickOption> searchAccountsByName(
    String searchTerm,
    Integer limitSize
  ) {
    if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
      return new List<AccountPickOption>();
    }
    Integer lim = limitSize == null ? 10 : limitSize;
    if (lim < 1) {
      lim = 1;
    }
    if (lim > 25) {
      lim = 25;
    }
    String term = searchTerm.trim();
    String likeKey = '%' + escapeForLike(term) + '%';
    Account[] rows = [
      SELECT Id, Name
      FROM Account
      WHERE Name LIKE :likeKey
      WITH SECURITY_ENFORCED
      ORDER BY Name
      LIMIT :lim
    ];
    List<AccountPickOption> out = new List<AccountPickOption>();
    for (Account a : rows) {
      AccountPickOption o = new AccountPickOption();
      o.value = String.valueOf(a.Id);
      o.label = a.Name;
      out.add(o);
    }
    return out;
  }

  private static String escapeForLike(String raw) {
    if (raw == null) {
      return '';
    }
    return raw.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
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
