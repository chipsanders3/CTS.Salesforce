public class BatchClientProspectMerge implements Database.Batchable<sObject> {
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        //Get a list of the clients that were uploaded.
        return Database.getQueryLocator(
            'SELECT Id, Name, AccountNumber, ParentId ' +
            'FROM Account ' +
            'WHERE RecordTypeId IN (SELECT Id FROM RecordType WHERE Name = \'Client\') ' +
            //'AND CreatedBy.Name = \'RGAImport\' ' +
            'AND DateMerged__c = null '
        );
    }

    public void execute(Database.BatchableContext bc, List<Account> records) {
        //For each client, look for similar client records and merge them together.
        for (Account masterAccount : records) {
            //Find duplicate accounts.
            List<Account> duplicates = FindDupes(masterAccount);
            List<Account> dupesToMerge = new List<Account>();
            
            //When matches are found, merge the details from the old (duplicate) records into the new (master) record.
            //From https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/langCon_apex_dml_examples_merge.htm
            //"Using the Apex merge operation, field values on the master record always supersede the 
            //corresponding field values on the records to be merged. To preserve a merged record 
            //field value, simply set this field value on the master sObject before performing the merge."

            //TBD: Business Rules for when to preserve values from the duplicates over to the master.
            if (!duplicates.isEmpty() && duplicates[0].Phone != null) { masterAccount.Phone = duplicates[0].Phone; }
            update masterAccount;

            while (!duplicates.isEmpty()) {
                //Merge two duplicates at a time to minimize DML executions.
                while (!duplicates.isEmpty() && dupesToMerge.size() < 2) {
                    dupesToMerge.add(duplicates.remove(0));
                }

                try { 
                    merge masterAccount dupesToMerge; 

                    masterAccount.DateMerged__c = DateTime.now();
                    update masterAccount;

                    // TODO: Logging/reporting
                } 
                catch(DmlException e) { 
                    HandleDmlException(e); 
                }

                dupesToMerge.clear();
            }

            //System.debug('DML Statements: ' + Limits.getDMLStatements() + ', ' + masterAccount.Name);
            //System.debug('SOQL Queries: ' + Limits.getQueries() + ', ' + masterAccount.Name);
        }
    }

    public void finish(Database.BatchableContext bc) { }

    private List<Account> FindDupes(Account account) {
        List<Account> duplicates = new List<Account>();

        for (Opportunity opp : [SELECT Account.Id, Account.Phone FROM Opportunity
                                WHERE BankAccountDetail__c IN
                                (SELECT Id FROM BankAccountDetail__c
                                 WHERE Account__r.Id = :account.Id)]) {
            duplicates.add(opp.Account);
        }

        return duplicates;
    }
    
    //TBD: How to handle exceptions?
    private void HandleDmlException(DmlException e) {
        for (Integer i = 0; i < e.getNumDml(); i++) {
            System.debug('DmlMessage: ' + e.getDmlMessage(i)); 
            System.debug('Status Code: ' + e.getDmlType(i)); 
            for(string fieldName : e.getDmlFieldNames(i)) {
                System.debug('Dml Field Name: ' + fieldName); 
            }
        }
        System.debug('Stack Trace: ' + e.getStackTraceString()); 
    }
}