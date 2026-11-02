@isTest
private class de_Contract_Pdf_ServiceTest {
  @isTest
  static void savePdfToAccount_success() {
    Account a = new Account(Name = 'dePdfClient');
    insert a;

    Blob fakePdf = Blob.valueOf('%PDF-1.4 fake body for unit test');
    String b64 = EncodingUtil.base64Encode(fakePdf);

    Test.startTest();
    Id docId = de_Contract_Pdf_Service.savePdfToAccount(
      a.Id,
      b64,
      'de Test contract PDF'
    );
    Test.stopTest();

    System.assertNotEquals(null, docId, 'ContentDocument Id');
    List<ContentDocumentLink> links = [
      SELECT Id
      FROM ContentDocumentLink
      WHERE
        LinkedEntityId = :a.Id
        AND ContentDocumentId = :docId
    ];
    System.assertEquals(
      1,
      links.size(),
      'file should be linked to Account'
    );
  }

  @isTest
  static void savePdfToAccount_rejectsNonAccount() {
    Contact c = new Contact(LastName = 'deNoPdf');
    insert c;
    Boolean threw = false;
    try {
      de_Contract_Pdf_Service.savePdfToAccount(
        c.Id,
        EncodingUtil.base64Encode(Blob.valueOf('x')),
        't'
      );
    } catch (AuraHandledException e) {
      threw = true;
      System.assert(
        e.getMessage() != null && e.getMessage().length() > 0,
        e.getMessage()
      );
    }
    System.assert(threw, 'expected AuraHandledException');
  }
}
