public with sharing class GovAgentActions {
    public class Request {
        @InvocableVariable(required=true label='Use case ID') public Id useCaseId;
        @InvocableVariable(required=true label='Operation: inspect or prepare') public String operation;
    }
    public class Result {
        @InvocableVariable public String outcome;
        @InvocableVariable public String structuredAssessment;
    }
    @InvocableMethod(label='Gov inspect or prepare governance filing' description='Inspect a governance use case or prepare its versioned filing. Human reviewers make every sign-off decision. This action cannot approve or activate an agent.')
    public static List<Result> execute(List<Request> requests) {
        if (requests == null || requests.size() != 1) throw new GovService.GovernanceException('Process one use case per agent action.');
        Request request=requests[0];
        if (request.operation == 'prepare') GovService.prepare(request.useCaseId);
        else if (request.operation != 'inspect') throw new GovService.GovernanceException('Supported operations: inspect, prepare.');
        Result result=new Result();
        GovController.Workspace workspace=GovController.getWorkspace(request.useCaseId);
        result.outcome='Filing '+(workspace.filing == null ? 'not prepared' : workspace.filing.Status__c)+'; outstanding evidence controls: '+workspace.blockers;
        // Agent action output is grounded in records; no generated legal findings are stored as facts.
        result.structuredAssessment=JSON.serialize(new Map<String,Object>{'filing'=>workspace.filing,'controls'=>workspace.controls,'isCurrent'=>workspace.isCurrent,'releaseReady'=>workspace.releaseReady,'limitations'=>workspace.limitations});
        return new List<Result>{result};
    }
}
