/**
 * Parses Visiting Card JSON and creates Account (per company) + Contact records using standard fields.
 */
public with sharing class de_VisitingCard_Contact_Service {
  /** Top-level JSON envelope */
  public class CardEnvelope {
    public Integer total_cards_detected;
    public List<CardRow> cards;
  }

  public class CardRow {
    public Integer card_number;
    public String person_name;
    public String designation;
    public String company_name;
    public String phone;
    public String email;
    public String website;
    public String address;
    public String other_details;
    public String raw_text;
  }

  public class CreateContactsResult {
    @AuraEnabled
    public List<Id> contactIds { get; set; }
    @AuraEnabled
    public List<Id> accountIds { get; set; }
    @AuraEnabled
    public Integer contactsCreated { get; set; }
    @AuraEnabled
    public Integer accountsCreated { get; set; }
    @AuraEnabled
    public String message { get; set; }

    public CreateContactsResult() {
      contactIds = new List<Id>();
      accountIds = new List<Id>();
      contactsCreated = 0;
      accountsCreated = 0;
    }
  }

  public class FlowInput {
    @InvocableVariable(
      required=true
      label='Visiting Card JSON'
      description='JSON with total_cards_detected and cards[]. May be raw JSON, markdown code fences, or embedded in surrounding text (first balanced object is used).'
    )
    public String visitingCardJson;

    @InvocableVariable(
      required=false
      label='Account Id'
      description='Optional. When set, all contacts are created under this Account (no new Accounts from card company names).'
    )
    public String accountId;
  }

  public class FlowOutput {
    @InvocableVariable(
      label='Contact Ids'
      description='Semicolon-separated Contact Ids in card order.'
    )
    public String contactIdsJoined;

    @InvocableVariable(
      label='Account Ids'
      description='Semicolon-separated Account Ids created (deduped by company name within the batch).'
    )
    public String accountIdsJoined;

    @InvocableVariable(label='Contacts created')
    public Integer contactsCreated;

    @InvocableVariable(label='Accounts created')
    public Integer accountsCreated;

    @InvocableVariable(label='Status message')
    public String message;
  }

  /**
   * @param visitingCardJson JSON with total_cards_detected and cards[]. Tolerates markdown code fences or extra text around the object.
   * @param accountId        Optional. When set, every contact uses this AccountId; no Accounts are created from card company names.
   */
  @AuraEnabled
  public static CreateContactsResult createContactsFromVisitingCardJson(
    String visitingCardJson,
    String accountId
  ) {
    String payload = resolvePayload(visitingCardJson);
    CardEnvelope env = (CardEnvelope) JSON.deserialize(payload, CardEnvelope.class);
    if (env == null || env.cards == null || env.cards.isEmpty()) {
      throw new AuraHandledException('No cards found in JSON (missing or empty "cards" array).');
    }

    Id parentAccountId = resolveParentAccountId(accountId);

    List<Account> accountsToInsert = new List<Account>();
    Map<String, Id> companyKeyToAccountId = new Map<String, Id>();
    List<String> accountKeysForInsert = new List<String>();

    if (parentAccountId == null) {
      for (CardRow row : env.cards) {
        String displayName = trimOrNull(row.company_name);
        if (displayName == null) {
          displayName = 'Unknown company';
        }
        String dedupeKey = displayName.toLowerCase();
        if (companyKeyToAccountId.containsKey(dedupeKey)) {
          continue;
        }
        companyKeyToAccountId.put(dedupeKey, null);
        accountsToInsert.add(new Account(Name = truncate(displayName, 255)));
        accountKeysForInsert.add(dedupeKey);
      }

      if (!accountsToInsert.isEmpty()) {
        insert accountsToInsert;
        for (Integer i = 0; i < accountsToInsert.size(); i++) {
          companyKeyToAccountId.put(accountKeysForInsert[i], accountsToInsert[i].Id);
        }
      }
    }

    List<Contact> toInsert = new List<Contact>();
    for (CardRow row : env.cards) {
      Id accId;
      if (parentAccountId != null) {
        accId = parentAccountId;
      } else {
        String companyDisplay = trimOrNull(row.company_name);
        if (companyDisplay == null) {
          companyDisplay = 'Unknown company';
        }
        accId = companyKeyToAccountId.get(companyDisplay.toLowerCase());
      }

      NameParts np = splitPersonName(row.person_name);
      Contact c = new Contact();
      c.AccountId = accId;
      c.FirstName = truncate(np.firstName, 40);
      c.LastName = truncate(np.lastName, 80);
      c.Title = truncate(trimOrNull(row.designation), 128);
      c.Email = truncate(trimOrNull(row.email), 80);
      c.Phone = normalizePhone(trimOrNull(row.phone));
      c.MailingStreet = truncate(trimOrNull(row.address), 255);
      c.Description = buildContactDescription(row, parentAccountId != null);
      toInsert.add(c);
    }

    CreateContactsResult out = new CreateContactsResult();
    if (toInsert.isEmpty()) {
      out.message = 'No contacts to insert.';
      return out;
    }

    Database.SaveResult[] results = Database.insert(toInsert, false);
    List<String> errs = new List<String>();
    for (Integer i = 0; i < results.size(); i++) {
      if (results[i].isSuccess()) {
        out.contactIds.add(results[i].getId());
      } else {
        for (Database.Error err : results[i].getErrors()) {
          errs.add('Card ' + String.valueOf(i + 1) + ': ' + err.getMessage());
        }
      }
    }

    out.contactsCreated = out.contactIds.size();
    out.accountsCreated = accountsToInsert.size();
    out.accountIds = new List<Id>();
    for (Account a : accountsToInsert) {
      out.accountIds.add(a.Id);
    }
    if (!errs.isEmpty()) {
      out.message =
        'Inserted ' +
        out.contactsCreated +
        ' of ' +
        toInsert.size() +
        ' contacts. Errors: ' +
        String.join(errs, ' | ');
    } else if (parentAccountId != null) {
      out.message =
        'Created ' +
        out.contactsCreated +
        ' contact(s) on the selected Account (no new Accounts from card data).';
    } else {
      out.message = 'Created ' + out.contactsCreated + ' contact(s) and ' + out.accountsCreated + ' account(s).';
    }
    return out;
  }

  @InvocableMethod(
    label='Create Contacts from Visiting Card JSON'
    description='Parses Visiting Card JSON and creates Contacts. Optional Account Id links all contacts to that Account; otherwise Accounts are created from company names on the cards.'
    category='DE Visiting Cards'
  )
  public static List<FlowOutput> createContactsInvocable(List<FlowInput> inputs) {
    List<FlowOutput> outputs = new List<FlowOutput>();
    if (inputs == null || inputs.isEmpty()) {
      return outputs;
    }
    for (FlowInput inRow : inputs) {
      FlowOutput o = new FlowOutput();
      try {
        CreateContactsResult r = createContactsFromVisitingCardJson(
          inRow.visitingCardJson,
          inRow.accountId
        );
        o.contactIdsJoined = joinIds(r.contactIds);
        o.accountIdsJoined = joinIds(r.accountIds);
        o.contactsCreated = r.contactsCreated;
        o.accountsCreated = r.accountsCreated;
        o.message = r.message;
      } catch (Exception e) {
        o.contactIdsJoined = '';
        o.accountIdsJoined = '';
        o.contactsCreated = 0;
        o.accountsCreated = 0;
        o.message = e.getMessage();
      }
      outputs.add(o);
    }
    return outputs;
  }

  private static Id resolveParentAccountId(String accountIdStr) {
    if (String.isBlank(accountIdStr)) {
      return null;
    }
    Id accId;
    try {
      accId = Id.valueOf(accountIdStr.trim());
    } catch (Exception e) {
      throw new AuraHandledException('Invalid Account Id.');
    }
    Account[] rows = [SELECT Id FROM Account WHERE Id = :accId LIMIT 1];
    if (rows.isEmpty()) {
      throw new AuraHandledException('Account not found or not accessible.');
    }
    return rows[0].Id;
  }

  private static String resolvePayload(String visitingCardJson) {
    if (String.isBlank(visitingCardJson)) {
      throw new AuraHandledException('Visiting Card JSON is required.');
    }
    String trimmed = visitingCardJson.trim();
    String stripped = stripMarkdownFences(trimmed);
    try {
      JSON.deserialize(stripped, CardEnvelope.class);
      return stripped;
    } catch (Exception ignore) {
    }
    return stripMarkdownFences(extractFirstBalancedJson(trimmed));
  }

  private static String stripMarkdownFences(String s) {
    String t = s.trim();
    if (!t.startsWith('```')) {
      return t;
    }
    Integer firstNl = t.indexOf('\n');
    if (firstNl > 0) {
      t = t.substring(firstNl + 1);
    } else {
      t = t.substring(3).trim();
    }
    if (t.endsWith('```')) {
      t = t.substring(0, t.length() - 3).trim();
    }
    return t.trim();
  }

  /**
   * Best-effort: first `{` through the matching closing `}` (ignores nesting inside JSON strings for rare cases).
   */
  private static String extractFirstBalancedJson(String text) {
    Integer start = text.indexOf('{');
    if (start < 0) {
      throw new AuraHandledException('No JSON object found in Visiting Card JSON.');
    }
    Integer depth = 0;
    for (Integer j = start; j < text.length(); j++) {
      String ch = text.substring(j, j + 1);
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          return text.substring(start, j + 1);
        }
      }
    }
    throw new AuraHandledException('Unbalanced JSON braces in Visiting Card JSON.');
  }

  private class NameParts {
    String firstName;
    String lastName;
  }

  private static NameParts splitPersonName(String personName) {
    NameParts np = new NameParts();
    String p = trimOrNull(personName);
    if (p == null) {
      np.firstName = null;
      np.lastName = 'Unknown';
      return np;
    }
    Integer sp = p.indexOf(' ');
    if (sp < 0) {
      np.firstName = null;
      np.lastName = p;
      return np;
    }
    np.firstName = p.substring(0, sp).trim();
    np.lastName = p.substring(sp + 1).trim();
    if (String.isBlank(np.lastName)) {
      np.lastName = np.firstName;
      np.firstName = null;
    }
    return np;
  }

  private static String buildDescription(CardRow row) {
    List<String> parts = new List<String>();
    if (!String.isBlank(trimOrNull(row.website))) {
      parts.add('Website: ' + trimOrNull(row.website));
    }
    if (!String.isBlank(trimOrNull(row.other_details))) {
      parts.add(trimOrNull(row.other_details));
    }
    if (!String.isBlank(trimOrNull(row.raw_text))) {
      parts.add('--- Raw text ---\n' + trimOrNull(row.raw_text));
    }
    String combined = String.join(parts, '\n\n');
    return truncate(combined, 32000);
  }

  private static String buildContactDescription(CardRow row, Boolean useParentAccount) {
    List<String> head = new List<String>();
    if (useParentAccount && !String.isBlank(trimOrNull(row.company_name))) {
      head.add('Company on card: ' + trimOrNull(row.company_name));
    }
    String body = buildDescription(row);
    if (head.isEmpty()) {
      return body;
    }
    if (String.isBlank(body)) {
      return truncate(String.join(head, '\n\n'), 32000);
    }
    return truncate(String.join(head, '\n\n') + '\n\n' + body, 32000);
  }


  private static String normalizePhone(String phone) {
    if (phone == null) {
      return null;
    }
    String t = phone.trim();
    return truncate(t, 40);
  }

  private static String trimOrNull(String s) {
    if (s == null) {
      return null;
    }
    String t = s.trim();
    return t.length() == 0 ? null : t;
  }

  private static String truncate(String s, Integer maxLen) {
    if (s == null) {
      return null;
    }
    if (s.length() <= maxLen) {
      return s;
    }
    return s.substring(0, maxLen);
  }

  private static String joinIds(List<Id> ids) {
    if (ids == null || ids.isEmpty()) {
      return '';
    }
    List<String> s = new List<String>();
    for (Id i : ids) {
      s.add(String.valueOf(i));
    }
    return String.join(s, ';');
  }
}
