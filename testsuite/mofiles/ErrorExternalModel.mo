// name: ErrorExternalModel
// status: incorrect

model ErrorExternalModel
external "C";
end ErrorExternalModel;

// Result:
// Error processing file: ErrorExternalModel.mo
// [ErrorExternalModel.mo:4:1-6:23:writable] Error: Restriction violation: ErrorExternalModel is a model, which may not contain an external function declaration.
// 
// # Error encountered! Exiting...
// # Please check the error message and the flags.
// 
// Execution failed!
// endResult