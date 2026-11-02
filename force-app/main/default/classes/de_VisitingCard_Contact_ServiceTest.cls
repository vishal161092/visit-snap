@IsTest
private class de_VisitingCard_Contact_ServiceTest {
  private static final String SAMPLE_JSON =
    '{"total_cards_detected":2,"cards":['
    + '{"card_number":1,"person_name":"Rahul Sharma","designation":"Marketing Manager","company_name":"BRANDVISTA",'
    + '"phone":"+91 98765 43210","email":"rahul.sharma@brandvista.test","website":"www.brandvista.example",'
    + '"address":"Noida","other_details":"Tagline","raw_text":"raw one"},'
    + '{"card_number":2,"person_name":"Priya Nair","designation":"Engineer","company_name":"BRANDVISTA",'
    + '"phone":"+91 90000 00000","email":"priya.nair@brandvista.test","website":"",'
    + '"address":"Pune","other_details":"","raw_text":"raw two"}]}';

  @IsTest
  static void createContacts_fromVisitingCardJson_createsContactsAndSharedAccount() {
    Test.startTest();
    de_VisitingCard_Contact_Service.CreateContactsResult r = de_VisitingCard_Contact_Service.createContactsFromVisitingCardJson(
      SAMPLE_JSON,
      null
    );
    Test.stopTest();

    System.assertEquals(2, r.contactsCreated, r.message);
    System.assertEquals(1, r.accountsCreated);
    System.assertEquals(2, r.contactIds.size());
    System.assertEquals(1, r.accountIds.size());

    Contact[] rows = [
      SELECT FirstName, LastName, Email, Account.Name, Description
      FROM Contact
      WHERE Id IN :r.contactIds
    ];
    System.assertEquals(2, rows.size());
    Set<String> emails = new Set<String>();
    for (Contact c : rows) {
      emails.add(c.Email);
      System.assertEquals('BRANDVISTA', c.Account.Name);
      System.assert(c.Description == null || !c.Description.startsWith('Company on card:'));
    }
    System.assert(emails.contains('rahul.sharma@brandvista.test'));
    System.assert(emails.contains('priya.nair@brandvista.test'));
  }

  @IsTest
  static void createContacts_withParentAccount_linksAllContacts_noNewAccounts() {
    Account parent = new Account(Name = 'Parent Co');
    insert parent;

    Test.startTest();
    de_VisitingCard_Contact_Service.CreateContactsResult r = de_VisitingCard_Contact_Service.createContactsFromVisitingCardJson(
      SAMPLE_JSON,
      String.valueOf(parent.Id)
    );
    Test.stopTest();

    System.assertEquals(2, r.contactsCreated, r.message);
    System.assertEquals(0, r.accountsCreated);
    System.assertEquals(0, r.accountIds.size());

    Contact[] rows = [
      SELECT AccountId, Description
      FROM Contact
      WHERE Id IN :r.contactIds
    ];
    for (Contact c : rows) {
      System.assertEquals(parent.Id, c.AccountId);
      System.assert(
        c.Description != null && c.Description.startsWith('Company on card:')
      );
    }
  }

  @IsTest
  static void createContacts_fromWrappedJson_extractsEnvelope() {
    String wrapped =
      'Here is the result:\n```json\n' + SAMPLE_JSON + '\n```\nThanks.';

    Test.startTest();
    de_VisitingCard_Contact_Service.CreateContactsResult r = de_VisitingCard_Contact_Service.createContactsFromVisitingCardJson(
      wrapped,
      null
    );
    Test.stopTest();

    System.assertEquals(2, r.contactsCreated, r.message);
  }

  @IsTest
  static void createContactsInvocable_returnsJoinedIds() {
    de_VisitingCard_Contact_Service.FlowInput fin = new de_VisitingCard_Contact_Service.FlowInput();
    fin.visitingCardJson = SAMPLE_JSON;
    fin.accountId = null;

    List<de_VisitingCard_Contact_Service.FlowOutput> outs = de_VisitingCard_Contact_Service.createContactsInvocable(
      new List<de_VisitingCard_Contact_Service.FlowInput>{ fin }
    );
    System.assertEquals(1, outs.size());
    System.assertEquals(2, outs[0].contactsCreated);
    System.assert(outs[0].contactIdsJoined.contains(';'));
  }

  @IsTest
  static void createContacts_blankInput_throws() {
    Boolean threw = false;
    try {
      de_VisitingCard_Contact_Service.createContactsFromVisitingCardJson(null, null);
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Expected AuraHandledException');

    threw = false;
    try {
      de_VisitingCard_Contact_Service.createContactsFromVisitingCardJson('   ', null);
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Expected AuraHandledException for blank');
  }

  @IsTest
  static void createContacts_deletedAccountId_throws() {
    Account a = new Account(Name = 'Deleted parent');
    insert a;
    Id deadId = a.Id;
    delete a;

    Boolean threw = false;
    try {
      de_VisitingCard_Contact_Service.createContactsFromVisitingCardJson(
        SAMPLE_JSON,
        String.valueOf(deadId)
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Expected AuraHandledException for missing Account');
  }
}
