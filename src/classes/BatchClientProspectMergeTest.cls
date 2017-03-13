@isTest
private class BatchClientProspectMergeTest {

	// Unit tests on Batchable Apex can only perform the execute statement once,
	// so limit the total number of master records to the batch size.
	private static Integer NUM_MASTERS = 50;
    private static Integer MOD_VALUE = 5;

    @testSetup
    static void setup() {
	    UserRole salesRole = [SELECT Id FROM UserRole 
	    		    		  WHERE Name = 'Channel Sales Team' LIMIT 1];
		Id sysAdminProfileId = [SELECT Id FROM Profile 
								WHERE Name = 'System Administrator' LIMIT 1].Id;
	    Id clientRecordId = [SELECT Id FROM RecordType
                 			 WHERE Name = 'Client' LIMIT 1].Id;

        // Create a RGAImport user
     	User rgaImportUser = new User(
     		LastName = 'RGAImport',
     		Alias = 'RGAImprt',
     		CommunityNickname = 'RGAImport',
     		Username = 'rga.import@salesforce.com',
     		Email = 'rga.import@salesforce.com',
     		EmailEncodingKey = 'UTF-8',
     		TimeZoneSidKey = 'America/New_York',
     		LocaleSidKey = 'en_US',
     		LanguageLocaleKey = 'en_US',
     		UserRole = salesRole,
     		ProfileId = sysAdminProfileId
 		);
 		insert rgaImportUser;

		List<Account> accounts = new List<Account>();
		List<BankAccountDetail__c> accountDetails = new List<BankAccountDetail__c>();
       	
       	System.runAs(rgaImportUser) {
       		// Create n master Clients (Accounts) as the RGAImport user; n = NUM_MASTERS
			for (Integer i = 0; i < NUM_MASTERS; i++) {
				Boolean mod = Math.mod(i, MOD_VALUE) == 0 ? false : true;

				accounts.add(new Account(
					AccountNumber = i < 10 ? '000' + i : '00' + i,
		            Name = 'Master Client ' + i,
		            BillingCity = mod ? 'New York' : 'Chicago',
		            BillingState = mod ? 'NY' : 'IL',
		            BillingCountry = 'USA',
		            Phone = mod ? null : '(312) 555-1234',
		            RecordTypeId = clientRecordId
				));
			}
	        insert accounts;

	        // Create 1 BankAccountDetail for each master Client
	        for (Account account : accounts) {
        		accountDetails.add(new BankAccountDetail__c(
        			Name = account.Name + ' Details',
        			Account__c = account.Id,
        			BankAccountNumber__c = account.AccountNumber
    			));
	        }
	        insert accountDetails;
    	}

		List<Account> duplicates = new List<Account>();

		// Create 1 duplicate Prospect for each master Client
    	for (Account account : accounts) {
    		Boolean isNY = account.BillingCity == 'New York';

        	duplicates.add(new Account(
    			AccountNumber = account.AccountNumber,
    			Name = 'Duplicate Client',
    			BillingCity = isNY ? 'Boulder' : 'Seattle',
    			BillingState = isNY ? 'CO' : 'WA',
    			BillingCountry = 'USA',
    			Phone = isNY ? '(720) 555-1234' : null
    		));
    	}
    	insert duplicates;

    	List<Opportunity> opportunities = new List<Opportunity>();

    	// Create 1 Opportunity (Pipeline) for each duplicate Prospect
        for (Account duplicate : duplicates) {
    		opportunities.add(new Opportunity(
				Name = 'Child Opportunity',
				CloseDate = Date.today(),
				StageName = 'Closed Won',
				AccountId = duplicate.Id,
				BankAccountDetail__c = [SELECT Id FROM BankAccountDetail__c
										WHERE Account__r.AccountNumber = :duplicate.AccountNumber].Id
			));
        }
        insert opportunities;
    }

    //TODO: Split up into multiple test methods
    @isTest
    static void test() {
        List<Account> accounts = [SELECT Id FROM Account];
        System.assertEquals(NUM_MASTERS * 2, accounts.size());
        
        Test.startTest();
        BatchClientProspectMerge batchMerge = new BatchClientProspectMerge();
        Database.executeBatch(batchMerge, 50);
        Test.stopTest();

        accounts = [SELECT Id FROM Account];
        System.assertEquals(NUM_MASTERS, accounts.size());

        List<Account> updatedNYAccounts = [SELECT BillingCity, Phone,
        								   (SELECT Id FROM Opportunities)
                                           FROM Account
                                           WHERE BillingState = 'NY'
                                           ORDER BY Name];

        List<Account> updatedILAccounts = [SELECT BillingCity, Phone,
        								   (SELECT Id FROM Opportunities)
                                           FROM Account
                                           WHERE BillingState = 'IL'
                                           ORDER BY Name];
        
        System.assertEquals(((MOD_VALUE - 1.0) / MOD_VALUE) * NUM_MASTERS, updatedNYAccounts.size());
        System.assertEquals(NUM_MASTERS / MOD_VALUE, updatedILAccounts.size());

        for (Account accountNY : updatedNYAccounts) {
	        System.assertEquals('New York', accountNY.BillingCity);
	        System.assertEquals('(720) 555-1234', accountNY.Phone);
	        System.assertEquals(1, accountNY.Opportunities.size());
   	 	}

   	 	for (Account accountIL : updatedILAccounts) {
	        System.assertEquals('Chicago', accountIL.BillingCity);
	        System.assertEquals('(312) 555-1234', accountIL.Phone);
	        System.assertEquals(1, accountIL.Opportunities.size());
        }
    }
}