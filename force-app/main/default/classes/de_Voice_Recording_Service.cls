/**
 * Creates a file on a record from base64 audio bytes (Salesforce Files / ContentVersion).
 */
public with sharing class de_Voice_Recording_Service {
  /**
   * @param recordId      Host record (e.g. Contact); file is linked via FirstPublishLocationId
   * @param base64        Raw base64 (no data: prefix)
   * @param pathOnClient  File name with extension, e.g. voice_2025.webm
   * @param title         File title shown in Files
   * @return ContentDocument Id of the created file
   */
  @AuraEnabled
  public static Id saveAudioToRecord(
    Id recordId,
    String base64,
    String pathOnClient,
    String title
  ) {
    if (recordId == null) {
      throw new AuraHandledException('A record is required to save the recording.');
    }
    if (String.isBlank(base64)) {
      throw new AuraHandledException('No audio data to save.');
    }
    if (String.isBlank(pathOnClient)) {
      pathOnClient = 'voice_recording.webm';
    }
    if (String.isBlank(title)) {
      title = 'Voice recording';
    }

    String normalized = base64;
    if (base64.contains(',')) {
      normalized = base64.substringAfter(',');
    }
    // Do not use replaceAll('\\s', ...) on large strings: can throw "Regex too complicated".
    normalized = stripWhitespaceForBase64(normalized);

    Blob fileBody;
    try {
      fileBody = EncodingUtil.base64Decode(normalized);
    } catch (Exception e) {
      throw new AuraHandledException('Invalid base64 data.');
    }
    if (fileBody == null || fileBody.size() == 0) {
      throw new AuraHandledException('Decoded audio is empty.');
    }

    ContentVersion cv = new ContentVersion();
    cv.Title = title;
    cv.PathOnClient = pathOnClient;
    cv.VersionData = fileBody;
    cv.FirstPublishLocationId = recordId;
    insert cv;

    Id versionId = cv.Id;
    ContentVersion inserted = [
      SELECT Id, ContentDocumentId
      FROM ContentVersion
      WHERE Id = :versionId
      LIMIT 1
    ];
    if (inserted.ContentDocumentId == null) {
      throw new AuraHandledException('File was created but not linked. Contact your admin.');
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
