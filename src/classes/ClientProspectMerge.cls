public class ClientProspectMerge implements Schedulable {
    
    // Each batch can process a max of 50 records as long as there no more 
    // than 2 duplicates per master record.
    public void execute(SchedulableContext ctx) {
        BatchClientProspectMerge batchMerge = new BatchClientProspectMerge();
        Database.executeBatch(batchMerge, 50);
    }

}