@isTest
private class de_CaseConflictServiceTest {
  @isTest
  static void type1_twoOwnersSameAccount() {
    Account acc = new Account(Name = 'deClientT1');
    insert acc;

    Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
    String ts = String.valueOf(System.currentTimeMillis());
    User b = new User(
      FirstName = 'de',
      LastName = 'PartnerB',
      Email = 'de.b.' + ts + '@example.com',
      Username = 'de.b.' + ts + '@example.com.test',
      Alias = 'dparb',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = p.Id
    );
    insert b;
    b = [SELECT Name FROM User WHERE Id = :b.Id];

    Case aCase = new Case(Subject = 'T1A', AccountId = acc.Id, Status = 'New', Origin = 'Web');
    insert aCase;
    Case bCase = new Case(Subject = 'T1B', AccountId = acc.Id, Status = 'New', Origin = 'Web');
    bCase.OwnerId = b.Id;
    insert bCase;

    de_CaseConflictService.de_ConflictResult r1 = de_CaseConflictService.getConflictForCase(
      aCase.Id
    );
    System.assert(
      r1.hasConflict,
      'Type1: same account, two open cases, different partners'
    );
    System.assert(
      r1.conflictType == 'TYPE1' || r1.conflictType == 'BOTH',
      r1.conflictType
    );
    System.assert(
      r1.rows != null,
      'rows'
    );
    System.assert(
      r1.rows.size() > 0
    );
    System.assert(
      r1.message != null
        && r1.message.contains(
          b.Name
        ),
      'summary should name the other partner: ' + r1.message
    );
    System.assertEquals(
      b.Name,
      r1.rows[0].otherPartnerName
    );
    System.assertEquals(
      aCase.Id,
      r1.rows[0].forCaseId,
      'row should name the open matter the conflict was evaluated against (your case)'
    );
    System.assertEquals(
      'deClientT1',
      r1.rows[0].clientName,
      'primary client name for the evaluated matter'
    );
  }

  @isTest
  static void getConflictForAccount_aggregates() {
    Account acc = new Account(Name = 'deAccScope');
    insert acc;

    Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
    String ts3 = String.valueOf(System.currentTimeMillis()) + '3';
    User b = new User(
      FirstName = 'de',
      LastName = 'ScopeB',
      Email = 'de.s.' + ts3 + '@example.com',
      Username = 'de.s.' + ts3 + '@example.com.test',
      Alias = 'dscb',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = p.Id
    );
    insert b;

    Case aCase = new Case(Subject = 'S1', AccountId = acc.Id, Status = 'New', Origin = 'Web');
    insert aCase;
    Case bCase = new Case(Subject = 'S2', AccountId = acc.Id, Status = 'New', Origin = 'Web');
    bCase.OwnerId = b.Id;
    insert bCase;

    de_CaseConflictService.de_ConflictResult r = de_CaseConflictService.getConflictForAccount(
      acc.Id
    );
    System.assert(
      r.hasConflict,
      'Account scope: two open same-account cases, two owners: ' + r.message
    );
  }

  @isTest
  static void type1_clientPrimaryOnMineAdverseOnOther() {
    Account clientAcc = new Account(Name = 'deClientSide');
    Account otherAcc = new Account(Name = 'deOtherSide');
    insert new List<Account> {clientAcc, otherAcc};

    Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
    String ts = String.valueOf(System.currentTimeMillis()) + 'adv';
    User b = new User(
      FirstName = 'de',
      LastName = 'AdvOwn',
      Email = 'de.adv.' + ts + '@example.com',
      Username = 'de.adv.' + ts + '@example.com.test',
      Alias = 'dadv',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = p.Id
    );
    insert b;

    Case mine = new Case(
      Subject = 'MinePrimary',
      AccountId = clientAcc.Id,
      Status = 'New',
      Origin = 'Web'
    );
    insert mine;
    Case theirs = new Case(
      Subject = 'TheirsAdv',
      AccountId = otherAcc.Id,
      de_Adverse_Client__c = clientAcc.Id,
      Status = 'New',
      Origin = 'Web'
    );
    theirs.OwnerId = b.Id;
    insert theirs;

    de_CaseConflictService.de_ConflictResult r = de_CaseConflictService.getConflictForCase(
      mine.Id
    );
    System.assert(
      r.hasConflict,
      'Type1 should see same client when other matter lists client only as adverse: ' + r.message
    );
    System.assert(
      r.conflictType == 'TYPE1' || r.conflictType == 'BOTH',
      r.conflictType
    );
    Boolean hasT1Row = false;
    if (r.rows != null) {
      for (de_CaseConflictService.de_ConflictRow row : r.rows) {
        if (row != null && row.caseId == theirs.Id) {
          hasT1Row = true;
          break;
        }
      }
    }
    System.assert(
      hasT1Row,
      'expected Type1 row for partner case with client as adverse'
    );
  }

  @isTest
  static void type1_singleOwner() {
    Account acc = new Account(Name = 'deSolo');
    insert acc;
    Case aCase = new Case(Subject = 'Solo1', AccountId = acc.Id, Status = 'New', Origin = 'Web');
    insert aCase;
    de_CaseConflictService.de_ConflictResult r = de_CaseConflictService.getConflictForCase(
      aCase.Id
    );
    System.assert(
      r.hasConflict == false,
      'one open case => no Type1'
    );
  }

  @isTest
  static void type2_fullPair() {
    Account partyP = new Account(Name = 'dePartyP');
    Account partyA = new Account(Name = 'dePartyA');
    insert new List<Account> {partyP, partyA};

    Profile pr = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
    String ts2 = String.valueOf(System.currentTimeMillis()) + '2';
    User b = new User(
      FirstName = 'de',
      LastName = 'Othr',
      Email = 'de.o.' + ts2 + '@example.com',
      Username = 'de.o.' + ts2 + '@example.com.test',
      Alias = 'dprto',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = pr.Id
    );
    insert b;

    Case c1 = new Case(
      Subject = 'C1',
      AccountId = partyP.Id,
      de_Adverse_Client__c = partyA.Id,
      Status = 'New',
      Origin = 'Web'
    );
    insert c1;
    Case c2 = new Case(
      Subject = 'C2',
      AccountId = partyA.Id,
      de_Adverse_Client__c = partyP.Id,
      Status = 'New',
      Origin = 'Web'
    );
    c2.OwnerId = b.Id;
    insert c2;

    de_CaseConflictService.de_ConflictResult r = de_CaseConflictService.getConflictForCase(c1.Id);
    System.assert(
      r.hasConflict,
      'inverse pair different owner: ' + r.message
    );
  }

  /**
   * Same partner Case can satisfy Type1 (shared party / different owner) and Type2 (full pair).
   * Rows must not dedupe across types or the UI loses an entire section.
   */
  @isTest
  static void bothTypes_twoRowsSameOtherCase() {
    Account partyP = new Account(Name = 'deBothP');
    Account partyA = new Account(Name = 'deBothA');
    insert new List<Account> {partyP, partyA};

    Profile pr = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
    String tsb = String.valueOf(System.currentTimeMillis()) + 'both';
    User b = new User(
      FirstName = 'de',
      LastName = 'BothO',
      Email = 'de.both.' + tsb + '@example.com',
      Username = 'de.both.' + tsb + '@example.com.test',
      Alias = 'dbth',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = pr.Id
    );
    insert b;

    Case c1 = new Case(
      Subject = 'Both1',
      AccountId = partyP.Id,
      de_Adverse_Client__c = partyA.Id,
      Status = 'New',
      Origin = 'Web'
    );
    insert c1;
    Case c2 = new Case(
      Subject = 'Both2',
      AccountId = partyA.Id,
      de_Adverse_Client__c = partyP.Id,
      Status = 'New',
      Origin = 'Web'
    );
    c2.OwnerId = b.Id;
    insert c2;

    de_CaseConflictService.de_ConflictResult r = de_CaseConflictService.getConflictForCase(c1.Id);
    System.assert(
      r.hasConflict,
      r.message
    );
    System.assertEquals(
      'BOTH',
      r.conflictType,
      'same other matter can be Type1 and Type2: ' + r.conflictType
    );
    Integer t1 = 0;
    Integer t2 = 0;
    if (r.rows != null) {
      for (de_CaseConflictService.de_ConflictRow row : r.rows) {
        if (row != null && row.caseId == c2.Id) {
          String tl = row.typeLabel == null ? '' : row.typeLabel.toLowerCase();
          if (tl.contains('same client') || tl.contains('type 1')) {
            t1++;
          }
          if (tl.contains('cross-party') || tl.contains('type 2')) {
            t2++;
          }
        }
      }
    }
    System.assertEquals(
      1,
      t1,
      'expected Type1 row for partner case'
    );
    System.assertEquals(
      1,
      t2,
      'expected Type2 row for partner case'
    );
  }

  @isTest
  static void closedSkips() {
    Account acc = new Account(Name = 'deClosed');
    insert acc;
    Case aCase = new Case(
      Subject = 'C',
      AccountId = acc.Id,
      Status = 'New',
      Origin = 'Web'
    );
    insert aCase;
    aCase.Status = 'Closed';
    update aCase;
    de_CaseConflictService.de_ConflictResult r = de_CaseConflictService.getConflictForCase(
      aCase.Id
    );
    System.assert(
      r.hasConflict == false,
      'closed: ' + r.message
    );
  }

  @isTest
  static void getConflictForCurrentPartner_seesOwnedMatter() {
    Account acc = new Account(Name = 'dePScope');
    insert acc;

    Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
    String ts = String.valueOf(System.currentTimeMillis()) + 'P';
    User b = new User(
      FirstName = 'de',
      LastName = 'POther',
      Email = 'de.po.' + ts + '@example.com',
      Username = 'de.po.' + ts + '@example.com.test',
      Alias = 'dpo',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = p.Id
    );
    insert b;

    Case aCase = new Case(Subject = 'PS1', AccountId = acc.Id, Status = 'New', Origin = 'Web');
    insert aCase;
    Case bCase = new Case(Subject = 'PS2', AccountId = acc.Id, Status = 'New', Origin = 'Web');
    bCase.OwnerId = b.Id;
    insert bCase;

    de_CaseConflictService.de_ConflictResult r = de_CaseConflictService.getConflictForCurrentPartner();
    System.assert(
      r.hasConflict,
      'Partner: should evaluate owned open case and see Type1: ' + r.message
    );
  }

  /**
   * Home merge: Type1 must use adverse as well as primary — partner’s matter may only share the
   * real client on AccountId while yours lists that client only as de_Adverse_Client__c.
   */
  @isTest
  static void getConflictForCurrentPartner_type1ViaSharedAdverseParty() {
    Account shell = new Account(Name = 'deShellCo');
    Account realClient = new Account(Name = 'deRealClientCo');
    insert new List<Account> {shell, realClient};

    Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
    String ts = String.valueOf(System.currentTimeMillis()) + 'advhome';
    User b = new User(
      FirstName = 'de',
      LastName = 'HomeOthr',
      Email = 'de.ho.' + ts + '@example.com',
      Username = 'de.ho.' + ts + '@example.com.test',
      Alias = 'dhom',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = p.Id
    );
    insert b;

    Case mine = new Case(
      Subject = 'HomeMine',
      AccountId = shell.Id,
      de_Adverse_Client__c = realClient.Id,
      Status = 'New',
      Origin = 'Web'
    );
    insert mine;
    Case theirs = new Case(
      Subject = 'HomeTheirs',
      AccountId = realClient.Id,
      Status = 'New',
      Origin = 'Web'
    );
    theirs.OwnerId = b.Id;
    insert theirs;

    de_CaseConflictService.de_ConflictResult r = de_CaseConflictService.getConflictForCurrentPartner();
    System.assert(
      r.hasConflict,
      'Partner home: Type1 via shared party (adverse on mine, primary on theirs): ' + r.message
    );
    Boolean sawT1 = false;
    if (r.rows != null) {
      for (de_CaseConflictService.de_ConflictRow row : r.rows) {
        if (row != null && row.caseId == theirs.Id) {
          String tl = row.typeLabel == null ? '' : row.typeLabel.toLowerCase();
          if (tl.contains('same client') || tl.contains('type 1')) {
            sawT1 = true;
            break;
          }
        }
      }
    }
    System.assert(
      sawT1,
      'expected a Type1-style row for partner case sharing real client; rows=' + r.rows
    );
  }

  @isTest
  static void getConflictForCurrentPartner_userWithNoOpenCases() {
    Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
    String ts = String.valueOf(System.currentTimeMillis()) + 'Q';
    User plain = new User(
      FirstName = 'de',
      LastName = 'NoOpen',
      Email = 'de.no.' + ts + '@example.com',
      Username = 'de.no.' + ts + '@example.com.test',
      Alias = 'dnop',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = p.Id
    );
    insert plain;

    System.runAs(plain) {
      de_CaseConflictService.de_ConflictResult r = de_CaseConflictService.getConflictForCurrentPartner();
      System.assert(
        r.hasConflict == false
      );
      System.assert(
        r.message != null
          && r.message.toLowerCase()
            .contains('no open')
      );
    }
  }

  @isTest
  static void getConflictForContact_aggregatesMatter() {
    Account acc = new Account(Name = 'deCtc');
    insert acc;
    Contact poc = new Contact(LastName = 'dePoc', AccountId = acc.Id);
    insert poc;
    Case k = new Case(
      Subject = 'POC1',
      AccountId = acc.Id,
      ContactId = poc.Id,
      Status = 'New',
      Origin = 'Web'
    );
    insert k;

    de_CaseConflictService.de_ConflictResult r = de_CaseConflictService.getConflictForContact(
      poc.Id
    );
    System.assert(
      r.hasConflict == false
    );
  }
}
