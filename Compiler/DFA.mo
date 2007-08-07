package DFA "
This file is part of OpenModelica.

Copyright (c) 1998-2006, Linkopings universitet, Department of
Computer and Information Science, PELAB

All rights reserved.

(The new BSD license, see also
http://www.opensource.org/licenses/bsd-license.php)


Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

 Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.

 Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in
  the documentation and/or other materials provided with the
  distribution.

 Neither the name of Linkopings universitet nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
\"AS IS\" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

  
  file:	 DFA.mo
  module:      DFA
  description: DFA intermediate form
"

public import Absyn;
public import Matrix;
public import Env;
public import Types;
public import ClassInf;
public import SCode;

type Stamp = Integer;
type ArcName = Absyn.Ident;
type SimpleStateArray = SimpleState[:];

protected import Lookup;
protected import Util;

public uniontype Dfa
  record DFArec
    list<Absyn.ElementItem> localVarList;
    list<Absyn.ElementItem> pathVarList; // Not in use
    Option<Matrix.RightHandSide> elseCase;
    State startState;
    Integer numOfStates; 
    Integer numOfCases; // The number of match cases in the 
                        // original match expression 
  end DFArec;
end Dfa;

public uniontype State
  record STATE
    Stamp stamp;
    Integer refCount; // Not in use
    list<Arc> outgoingArcs;
    Option<Matrix.RightHandSide> rhSide;
  end STATE;
  
  record DUMMIESTATE  
  end DUMMIESTATE; 
  
  record GOTOSTATE 
    Stamp stamp;
    Stamp toState;
  end GOTOSTATE;
end State;

public uniontype Arc
  record ARC
    State state;
    ArcName arcName;
    Option<Matrix.RenamedPat> pat; 
    list<Integer> matchCaseNumbers; // The numbers of the righthand sides  
                                    // that this arc leads to.
  end ARC;
end Arc;

// This data structure is used in the optimization phase in Patternm.
// A list/array of SimpleStates is used as a "light" version of
// the DFA.
public uniontype SimpleState
  record SIMPLESTATE 
    Stamp stamp; 
    list<ArcName,Stamp> outgoingArcs; // Name of arc and the number of the state that the arc leads to
    Integer caseNum; // This one is zero if it's not a final state 
    Option<Absyn.Ident> varName; // The state variable
  end SIMPLESTATE;   
  
  record SIMPLEDUMMIE 
  end SIMPLEDUMMIE;
end SimpleState;  


public function addNewArc "function: addNewArc
	author: KS
	A function that adds a new arc to a states arc-list
"
  input State firstState;
  input ArcName arcName; 
  input State newState;
  input Option<Matrix.RenamedPat> pat; 
  input list<Integer> caseNumbers;
  output State outState;
algorithm
  outState :=
  matchcontinue (firstState,arcName,newState,pat,caseNumbers)
    case (STATE(localStamp,localRefCount,localOutArcs,localRhSide),
        localArcName,localNewState,localPat,localCaseNumbers)
      local
        State localFirstState;
        ArcName localArcName;
        State localNewState;
        Stamp localStamp;
        Integer localRefCount;
        list<Arc> localOutArcs;
        Option<Matrix.RightHandSide> localRhSide;
        Arc newArc;
        Option<Matrix.RenamedPat> localPat; 
        list<Integer> localCaseNumbers;
      equation
        newArc = ARC(localNewState,localArcName,localPat,localCaseNumbers);    
        localOutArcs = listAppend(localOutArcs,(newArc :: {}));  
        localFirstState = STATE(localStamp,localRefCount,localOutArcs,localRhSide);
      then localFirstState;
  end matchcontinue;    
end addNewArc;  

public function fromDFAtoIfNodes "function: fromDFAtoIfNodes
	author: KS
	Main function for converting a DFA into a valueblock expression containing
	if-statements.
"
  input Dfa dfa;
  input list<Absyn.Exp> inputVarList; // matchcontinue (var1,var2,...)
  input list<Absyn.Exp> resVarList;  // (var1,var2,...) := matchcontinue (...) ...
  input Env.Cache cache;
  input Env.Env env; 
  input Matrix.RightHandList rightSideList;
  output Env.Cache outCache;
  output Absyn.Exp outExp;
algorithm
  (outCache,outExp) :=
  matchcontinue (dfa,inputVarList,resVarList,cache,env,rightSideList)
    local
      list<Absyn.ElementItem> localVarList,varList;
      Option<Matrix.RightHandSide> elseCase;
      State startState;
      Absyn.Exp exp,resExpr,arrayOfTrue;
      list<Absyn.AlgorithmItem> algs;
      Integer numCases;
      Absyn.Exp statesList;
      Env.Cache localCache;
      Env.Env localEnv; 
      list<Absyn.Exp> expList,localResVarList,localInputVarList,listOfTrue; 
      Matrix.RightHandList localRightSideList;
    case (DFArec(localVarList,_,elseCase,startState,_,numCases),localInputVarList, 
        localResVarList,localCache,localEnv,localRightSideList)
      equation 

        // Used for catch handling. Keep track of the last righthand side visited.		        
        varList = {Absyn.ELEMENTITEM(Absyn.ELEMENT(
          false,NONE(),Absyn.UNSPECIFIED(),"component",
          Absyn.COMPONENTS(Absyn.ATTR(false,Absyn.VAR(),Absyn.BIDIR(),{}),
            Absyn.TPATH(Absyn.IDENT("Integer"),NONE()),		
            {Absyn.COMPONENTITEM(Absyn.COMPONENT("LASTRIGHTHANDSIDE__",{},NONE()),NONE(),NONE())}),
            Absyn.INFO("f",false,0,0,0,0),NONE()))};
        
        localVarList = listAppend(localVarList,varList);
        
        //The variable BOOLVAR__ should be initialized with true
        listOfTrue = createListOfTrue(numCases,{});
        arrayOfTrue = Absyn.ARRAY(listOfTrue);
        
        // This variable is used for catch handling. It should be an array.
      /*  varList = {Absyn.ELEMENTITEM(Absyn.ELEMENT(
          false,NONE(),Absyn.UNSPECIFIED(),"component",
          Absyn.COMPONENTS(Absyn.ATTR(false,Absyn.VAR(),Absyn.BIDIR(),{}),
            Absyn.TPATH(Absyn.IDENT("Integer"),NONE()),		
            {Absyn.COMPONENTITEM(Absyn.COMPONENT("BOOLVAR__",{Absyn.SUBSCRIPT(Absyn.INTEGER(numCases))},SOME(Absyn.CLASSMOD({},SOME(arrayOfTrue)))),NONE(),NONE())}),
            Absyn.INFO("f",false,0,0,0,0),NONE()))}; 
        
        localVarList = listAppend(localVarList,varList); */
        
        // This variable is a dummie variable, used when we want to use a valueblock but not
        // return anything interesting. DUMMIE__ := VALUEBLOCK( ... )      
        varList = {Absyn.ELEMENTITEM(Absyn.ELEMENT(
          false,NONE(),Absyn.UNSPECIFIED(),"component",
          Absyn.COMPONENTS(Absyn.ATTR(false,Absyn.VAR(),Absyn.BIDIR(),{}),
            Absyn.TPATH(Absyn.IDENT("Boolean"),NONE()),		
            {Absyn.COMPONENTITEM(Absyn.COMPONENT("DUMMIE__",{},SOME(Absyn.CLASSMOD({},SOME(Absyn.BOOL(true))))),NONE(),NONE())}),
            Absyn.INFO("f",false,0,0,0,0),NONE()))};
        
        localVarList = listAppend(localVarList,varList);
        
        // This boolean variable is used with the catch handling
        varList = {Absyn.ELEMENTITEM(Absyn.ELEMENT(
          false,NONE(),Absyn.UNSPECIFIED(),"component",
          Absyn.COMPONENTS(Absyn.ATTR(false,Absyn.VAR(),Absyn.BIDIR(),{}),
            Absyn.TPATH(Absyn.IDENT("Boolean"),NONE()),		
            {Absyn.COMPONENTITEM(Absyn.COMPONENT("NOTDONE__",{},SOME(Absyn.CLASSMOD({},SOME(Absyn.BOOL(true))))),NONE(),NONE())}),
            Absyn.INFO("f",false,0,0,0,0),NONE()))};
        
        localVarList = listAppend(localVarList,varList);
        
        (localCache,algs,varList) = generateAlgorithmBlock(localResVarList,localInputVarList,startState, 
          elseCase,localCache,localEnv,localRightSideList);
       
        // This varList contains new variables introduced in connection with constructor-call
        // patterns
        localVarList = listAppend(localVarList,varList);
        
        resExpr = Util.listFirst(localResVarList);
        
        //Create the main valueblock
        exp = Absyn.VALUEBLOCK(localVarList,Absyn.VALUEBLOCKALGORITHMS(algs),resExpr);
      then (localCache,exp);     
  end matchcontinue;
end fromDFAtoIfNodes;  

protected function generateAlgorithmBlock "function: generateAlgorithmBlock
	author: KS
 Generate the algorithm statements in the value block from the DFA
"
  input list<Absyn.Exp> resVarList; // Component references to the return list variables
  input list<Absyn.Exp> inputVarList; // matchcontinue (var1,var2,...)
  input State startState;
  input Option<Matrix.RightHandSide> elseCase;
  input Env.Cache cache;
  input Env.Env env;   
  input Matrix.RightHandList rightHandList;
  output Env.Cache outCache;
  output list<Absyn.AlgorithmItem> outAlgorithms; 
  output list<Absyn.ElementItem> outNewVars;
algorithm
  (outCache,outAlgorithms,outNewVars) :=
  matchcontinue (resVarList,inputVarList,startState,elseCase,cache,env,rightHandList)
    local
      Env.Cache localCache;
      Env.Env localEnv;     
      list<Absyn.Exp> localResVarList,localInputVarList; 
      list<Absyn.ElementItem> newVars; 
      Matrix.RightHandList localRightHandList;
    case (localResVarList,localInputVarList,localStartState,NONE(),localCache, 
        localEnv,localRightHandList) // NO ELSE-CASE    
      local
        State localStartState;
        list<Absyn.AlgorithmItem> algs,algs2;
        Absyn.AlgorithmItem algItem1,algItem2;
        list<tuple<Absyn.Ident,Absyn.TypeSpec>> dfaEnv;
      equation 
        // The DFA Environment is used to store the type of some path variables. It is used
        // when we want to get the type of a list variable. Since the input variables
        // are the outermost path variables, we add them to this environment. 
        (dfaEnv,localCache) = addVarsToDfaEnv(localInputVarList,{},localCache,localEnv);
        
        // while() {
        // try {
        // if (...)
        // ...
        // break();
        // ---- A NON-MATCH SHOULD BE HANDLED HERE ----
        // finalstate1:
        // ...
        // break();
        // ...
        // finalstateN: 
        // ...
        // break();
        // } catch (int i) {
        // BOOLVAR__[LASTRIGHTHANDSIDE__] = 0;
        //}
        // }
        (localCache,algs,newVars) = fromStatetoAbsynCode(localStartState,NONE(),localCache,localEnv,dfaEnv,{}); 
        //------
        algs = listAppend(algs,{Absyn.ALGORITHMITEM(Absyn.ALG_BREAK(),NONE())});        
        algs2 = generateFinalStates(localRightHandList,{},localResVarList);
        algs = listAppend(algs,algs2);
        //------

        algItem1 = Absyn.ALGORITHMITEM(Absyn.ALG_TRY(algs),NONE());  
      //  algItem2 = Absyn.ALGORITHMITEM(Absyn.ALG_CATCH({Absyn.ALGORITHMITEM(Absyn.ALG_ASSIGN(Absyn.CREF(
      // Absyn.CREF_IDENT("BOOLVAR__",{Absyn.SUBSCRIPT(Absyn.CREF(Absyn.CREF_IDENT("LASTRIGHTHANDSIDE__",{})))})),
      //    Absyn.INTEGER(0)),NONE())}),NONE()); 
        algs = listAppend({algItem1},{}); //algItem2
        algs = {Absyn.ALGORITHMITEM(Absyn.ALG_WHILE(Absyn.BOOL(true)  
          ,algs),NONE())};
        
      then (localCache,algs,newVars);
   // ELSE-CASE     
    case (localResVarList,localInputVarList,localStartState,SOME(Matrix.RIGHTHANDSIDE(localVars,eqs,res,_)), 
        localCache,localEnv,localRightHandList) // AN ELSE-CASE EXIST
      local
        list<Absyn.EquationItem> eqs;
        list<Absyn.ElementItem> localVars;
        list<Absyn.AlgorithmItem> algList,algList2,algList3,bodyIf,algIf;
        Absyn.Exp res,resExpr;
        State localStartState;
        list<Absyn.Exp> expList;
        list<tuple<Absyn.Ident,Absyn.TypeSpec>> dfaEnv;
      equation
        // The DFA Environment is used to store the type of some path variables. It is used
        // when we want to get the type of a list variable. Since the input variables
        // are the outermost path variables, we add them to this environment. 
        (dfaEnv,localCache) = addVarsToDfaEnv(localInputVarList,{},localCache,localEnv);
        
        (localCache,algList,newVars) = fromStatetoAbsynCode(localStartState,NONE(),localCache,localEnv,dfaEnv,{});

        algList2 = fromEquationsToAlgAssignments(eqs,{});
        
        // Create result assignments
        expList = createListFromExpression(res);  
        algList3 = createLastAssignments(localResVarList,expList,{});
        
        algList2 = listAppend(algList2,algList3);
           
        bodyIf = {Absyn.ALGORITHMITEM(Absyn.ALG_ASSIGN(Absyn.CREF(Absyn.CREF_IDENT("DUMMIE__",{})),
          Absyn.VALUEBLOCK(localVars,Absyn.VALUEBLOCKALGORITHMS(algList2),Absyn.BOOL(true))),NONE())};
        
        algIf = {Absyn.ALGORITHMITEM(Absyn.ALG_IF(Absyn.CREF(
          Absyn.CREF_IDENT("NOTDONE__",{})),bodyIf,{},{}),NONE())};
          
        algList = listAppend(algList,algIf);
        algList = listAppend(algList,{Absyn.ALGORITHMITEM(Absyn.ALG_BREAK(),NONE())});
        //------
        algList2 = generateFinalStates(localRightHandList,{},localResVarList);
        algList = listAppend(algList,algList2);
        //------
        

        // while(NOTDONE__) {
        // try {
        // if (...)
        // ... 
        // if (NOTDONE__) {valueblock (<ELSE-CASE>)}
        // break();
        // ---- A NON-MATCH SHOULD BE HANDLED HERE ----
        // finalstate1:
        // ...
        // break();
        // ...
        // finalstateN: 
        // ...
        // break();
        // } catch (int i) {
        // BOOLVAR__[LASTRIGHTHANDSIDE__] = 0;
        //}
        // }
        algList2 = {Absyn.ALGORITHMITEM(Absyn.ALG_TRY(algList),NONE())}; 
       // algList3 = {Absyn.ALGORITHMITEM(Absyn.ALG_CATCH({Absyn.ALGORITHMITEM(Absyn.ALG_ASSIGN(Absyn.CREF(
       // Absyn.CREF_IDENT("BOOLVAR__",{Absyn.SUBSCRIPT(Absyn.CREF(Absyn.CREF_IDENT("LASTRIGHTHANDSIDE__",{})))})),
       //   Absyn.INTEGER(0)),NONE())}),NONE())};
        algList = listAppend(algList2,{}); // algList3
        algList = {Absyn.ALGORITHMITEM(Absyn.ALG_WHILE(Absyn.CREF(Absyn.CREF_IDENT("NOTDONE__",{}))  
          ,algList),NONE())};
        
      then (localCache,algList,newVars); 
  end matchcontinue;
end generateAlgorithmBlock;  

protected function generateFinalStates "function: generateFinalStates
Generates the final states.
        finalstate1:
         ...
         return();
         ...
         finalstateN: 
         ...
         return();
"
  input Matrix.RightHandList inList;
  input list<Absyn.AlgorithmItem> accList;
  input list<Absyn.Exp> resVarList; 
  output list<Absyn.AlgorithmItem> outList;  
algorithm 
  outList := 
  matchcontinue (inList,accList,resVarList)  
    local
      Matrix.RightHandList rest; 
      list<Absyn.AlgorithmItem> localAccList; 
      list<Absyn.Exp> localResVarList;
    case ({},localAccList,_) then localAccList; 
      // No local variables
    case (Matrix.RIGHTHANDSIDE({},equations,result,caseNum) :: rest,localAccList,localResVarList) 
      local
        Integer caseNum;
        list<Absyn.EquationItem> equations;
        Absyn.Exp result,resVars;
        list<Absyn.AlgorithmItem> outList,body,lastAssign,doneAssign,stateAssign;  
        String stateName; 
        Matrix.RightHandList rest; 
        list<Absyn.Exp> exp2;
      equation 
        // finalStateN:
        // LASTRIGHTHANDSIDE__ = caseNum;
        // <CODE>
        // resVar1 = ...;
        // ...
        // resVarX = ...;
        // NOTDONE__ = false;
        // break();
        
        exp2 = createListFromExpression(result);
        
        // Create the assignments that assigns the return variables
        lastAssign = createLastAssignments(localResVarList,exp2,{});
        
        body = fromEquationsToAlgAssignments(equations,{}); 
        stateAssign = {Absyn.ALGORITHMITEM(Absyn.ALG_ASSIGN(Absyn.CREF(Absyn.CREF_IDENT("LASTRIGHTHANDSIDE__",{})),
          Absyn.INTEGER(caseNum)),NONE())};
        outList = listAppend(stateAssign,body);
        outList = listAppend(outList,lastAssign);  
        
        // Set NOTDONE__ to false 
        doneAssign = {Absyn.ALGORITHMITEM(Absyn.ALG_ASSIGN(Absyn.CREF(Absyn.CREF_IDENT("NOTDONE__",{})),
          Absyn.BOOL(false)),NONE())};
        outList = listAppend(outList,doneAssign);
        
        stateName = stringAppend("finalstate",intString(caseNum));
        stateAssign = {Absyn.ALGORITHMITEM(Absyn.ALG_LABEL(stateName),NONE())}; 
        outList = listAppend(stateAssign,outList); 
        stateAssign = {Absyn.ALGORITHMITEM(Absyn.ALG_BREAK(),NONE())};
        outList = listAppend(outList,stateAssign);  
        
        localAccList = listAppend(localAccList,outList);
        localAccList = generateFinalStates(rest,localAccList,localResVarList);
      then localAccList; 
        
        // Local variables	
    case (Matrix.RIGHTHANDSIDE(localList,equations,result,caseNum) :: rest,localAccList,localResVarList) 
      local
        list<Absyn.EquationItem> equations;
        list<Absyn.ElementItem> localList;
        Absyn.Exp result,vBlock,resVars;
        list<Absyn.AlgorithmItem> outList,body,lastAssign,doneAssign,stateAssign;  
        String stateName; 
        Integer caseNum; 
        Matrix.RightHandList rest; 
        list<Absyn.Exp> exp2;
      equation    
        // finalstateN:	
        // { 
        // <VAR-DECL>
        // LASTRIGHTHANDSIDE = caseNum;
        // <CODE>
        // resVar1 = ...;
        // ...
        // resVarX = ...;
        // NOTDONE__ = false;
        // } 
        // break();
        exp2 = createListFromExpression(result);
    
        // Create the assignments that assign the return variables
        lastAssign = createLastAssignments(localResVarList,exp2,{});
        
        body = fromEquationsToAlgAssignments(equations,{}); 
        
        stateAssign = {Absyn.ALGORITHMITEM(Absyn.ALG_ASSIGN(Absyn.CREF(Absyn.CREF_IDENT("LASTRIGHTHANDSIDE__",{})),
          Absyn.INTEGER(caseNum)),NONE())}; 
        outList = listAppend(stateAssign,body); 
             
        outList = listAppend(outList,lastAssign);
        
        // Set NOTDONE__ to false 
        doneAssign = {Absyn.ALGORITHMITEM(Absyn.ALG_ASSIGN(Absyn.CREF(Absyn.CREF_IDENT("NOTDONE__",{})),
          Absyn.BOOL(false)),NONE())};
        outList = listAppend(outList,doneAssign);
        vBlock = Absyn.VALUEBLOCK(localList,Absyn.VALUEBLOCKALGORITHMS(outList),Absyn.BOOL(true));
        outList = {Absyn.ALGORITHMITEM(Absyn.ALG_ASSIGN(Absyn.CREF(Absyn.CREF_IDENT("DUMMIE__",{})),vBlock),NONE())};
        
        stateName = stringAppend("finalstate",intString(caseNum));
        stateAssign = {Absyn.ALGORITHMITEM(Absyn.ALG_LABEL(stateName),NONE())}; 
        outList = listAppend(stateAssign,outList);  
        
        stateAssign = {Absyn.ALGORITHMITEM(Absyn.ALG_BREAK(),NONE())};
        outList = listAppend(outList,stateAssign);  
        
        localAccList = listAppend(localAccList,outList);
        localAccList = generateFinalStates(rest,localAccList,localResVarList);
      then localAccList;
  end matchcontinue;
end generateFinalStates;


protected function fromStatetoAbsynCode "function: fromStatetoAbsynCode
 	author: KS
 	Takes a DFA state and recursively generates if-else nodes by investigating 
	 the outgoing arcs.
"
  input State state;
  input Option<Matrix.RenamedPat> inPat;
  input Env.Cache cache;
  input Env.Env env;
  input list<tuple<Absyn.Ident,Absyn.TypeSpec>> dfaEnv;  
  input list<Absyn.ElementItem> accNewVars;
  output Env.Cache outCache;  
  output list<Absyn.AlgorithmItem> ifNodes; 
  output list<Absyn.ElementItem> outNewVars; // New variables from Constructor-call patterns
algorithm
  (outCache,ifNodes,outNewVars) :=
  matchcontinue (state,inPat,cache,env,dfaEnv,accNewVars)
    local
      Stamp stamp;
      Absyn.Ident stateVar,localInStateVar;
      Matrix.RenamedPat localInPat,pat;
      Env.Cache localCache;
      Env.Env localEnv;
      list<tuple<Absyn.Ident,Absyn.TypeSpec>> localDfaEnv;
      list<Absyn.Exp> exp2;
      Integer localRetExpLen;
      String stateName; 
      list<Absyn.ElementItem> localAccNewVars;
      // JUST TO BE SURE    
    case (DUMMIESTATE(),_,localCache,_,_,localAccNewVars) equation then (localCache,{},localAccNewVars);
    
      // GOTO STATE	  
    case (GOTOSTATE(_,n),_,localCache,_,_,localAccNewVars)  
      local 
        list<Absyn.AlgorithmItem> outElems;  
        Integer n;
        String s; 
      equation   
        s = stringAppend("state",intString(n));
        outElems = {Absyn.ALGORITHMITEM(Absyn.ALG_GOTO(s),NONE())};
      then (localCache,outElems,localAccNewVars);
      
      //FINAL STATE  
    case(STATE(stamp,_,_,SOME(Matrix.RIGHTHANDLIGHT(n))),_,localCache,_,_,localAccNewVars)
      local  
        list<Absyn.AlgorithmItem> outList; 
        String s;  
        Integer n;
      equation  
        s = stringAppend("finalstate",intString(n));
        outList = {Absyn.ALGORITHMITEM(Absyn.ALG_GOTO(s),NONE())};   
      then (localCache,outList,localAccNewVars);
        
        // THIS IS A TEST STATE, INCOMING ARC WAS AN ELSE-ARC OR THIS IS THE FIRST STATE
    case (STATE(stamp,_,arcs as (ARC(_,_,SOME(pat),_) :: _),NONE()),NONE(),localCache,localEnv,localDfaEnv,localAccNewVars)    
      local
        list<Arc> arcs;
        list<Absyn.AlgorithmItem> algList,stateAssign;   
      equation 	
        
        (localCache,algList,localAccNewVars) = generateIfElseifAndElse(arcs,extractPathVar(pat),true,Absyn.INTEGER(0),{},{},localCache,localEnv,localDfaEnv,localAccNewVars);
        
        stateName = stringAppend("state",intString(stamp));
        stateAssign = {Absyn.ALGORITHMITEM(Absyn.ALG_LABEL(stateName),NONE())};  
        
        algList = listAppend(stateAssign,algList);
      then (localCache,algList,localAccNewVars); 		    		    
        
        // THIS IS A TEST STATE (INCOMING ARC WAS A CONSTRUCTOR, CONS OR CONSTRUCTOR-CALL)     
    case (STATE(stamp,_,arcs as (ARC(_,_,SOME(pat),_) :: _),NONE()),SOME(localInPat),localCache,localEnv,localDfaEnv,localAccNewVars)    
      local
        list<Arc> arcs;
        list<Absyn.AlgorithmItem> algList,bindings2,pathAssignList,stateAssign;
        list<Absyn.ElementItem> declList; 
        Absyn.Exp valueBlock;
      equation 
        true = constructorOrNot(localInPat);
        
        // The following function, generatePathVarDeclarations, will
        // generate new variables and bindings. For instance if we
        // have a record RECNAME{ TYPE1 field1, TYPE2 field2 } :
        // 
        // if (getType(x) = RECNAME)
        // stateN:
        // x__1 = x.field1;
        // x__2 = x.field2;
        // 
        // The new variables are added to the declaration section of the whole
        // pattern match statement.
        (localCache,localDfaEnv,declList,pathAssignList) = generatePathVarDeclarations(localInPat,localCache,localEnv,localDfaEnv);
        localAccNewVars = listAppend(localAccNewVars,declList);
        
        (localCache,algList,localAccNewVars) = 
        generateIfElseifAndElse(arcs,extractPathVar(pat),true,Absyn.INTEGER(0),{},{},localCache,localEnv,localDfaEnv,localAccNewVars);
      
        algList = listAppend(pathAssignList,algList);
        
        stateName = stringAppend("state",intString(stamp));
        stateAssign = {Absyn.ALGORITHMITEM(Absyn.ALG_LABEL(stateName),NONE())};
        algList = listAppend(stateAssign,algList);
        
      then (localCache,algList,localAccNewVars); 
              
        //TEST STATE,THE ARC TO THIS STATE WAS NOT A CONSTRUCTOR	    
    case(STATE(stamp,_,arcs as (ARC(_,_,SOME(pat),_) :: _),NONE()),SOME(localInPat),localCache,localEnv,localDfaEnv,localAccNewVars)			  	  
      local
        list<Arc> arcs;
        list<Absyn.AlgorithmItem> algList,stateAssign; 
      equation 
        (localCache,algList,localAccNewVars) = generateIfElseifAndElse(arcs,extractPathVar(pat),true,Absyn.INTEGER(0),{},{},localCache,localEnv,localDfaEnv,localAccNewVars);
        
        stateName = stringAppend("state",intString(stamp));
        stateAssign = {Absyn.ALGORITHMITEM(Absyn.ALG_LABEL(stateName),NONE())};
        algList = listAppend(stateAssign,algList);
        
      then (localCache,algList,localAccNewVars); 
  end matchcontinue;    
end fromStatetoAbsynCode;  


protected function createLastAssignments "function: createLastAssignments
	author: KS
	Creates the assignments that will assign the result variables
	the final values.
	(v1,v2...vN) := matchcontinue (x,y...)
                case (...) then (1,2,...N);
	Here v1,v2,...,vN should be assigned the values 1,2,...N.                
"
  input list<Absyn.Exp> lhsList;
  input list<Absyn.Exp> rhsList;
  input list<Absyn.AlgorithmItem> accList;
  output list<Absyn.AlgorithmItem> outList;
algorithm
  outList :=
  matchcontinue (lhsList,rhsList,accList)
    local
      list<Absyn.AlgorithmItem> localAccList;
    case ({},{},localAccList) then localAccList;
    case (firstLhs :: restLhs,firstRhs :: restRhs,localAccList)
      local
        Absyn.Exp firstLhs,firstRhs;
        list<Absyn.Exp> restLhs,restRhs;
        Absyn.AlgorithmItem elem;
      equation
        elem = Absyn.ALGORITHMITEM(Absyn.ALG_ASSIGN(firstLhs,firstRhs),NONE);
        localAccList = listAppend(localAccList,{elem});
        localAccList = createLastAssignments(restLhs,restRhs,localAccList);
      then localAccList;
  end matchcontinue;        
end createLastAssignments;


protected function generatePathVarDeclarations "function: generatePathVarDeclerations
	author: KS
	Used when we have a record constructor call in a pattern and we need to
	create path variables of the subpatterns of the record constructor.
"
  input Matrix.RenamedPat pat;
  input Env.Cache cache;
  input Env.Env env;   
  input list<tuple<Absyn.Ident,Absyn.TypeSpec>> dfaEnv;
  output Env.Cache outCache;
  output list<tuple<Absyn.Ident,Absyn.TypeSpec>> outDfaEnv;
  output list<Absyn.ElementItem> outDecl;
  output list<Absyn.AlgorithmItem> outAssigns;
algorithm
  (outCache,outDfaEnv,outDecl,outAssigns) :=
  matchcontinue (pat,cache,env,dfaEnv)
    local
      Env.Cache localCache;
      Env.Env localEnv; 
      list<tuple<Absyn.Ident,Absyn.TypeSpec>> localDfaEnv;
    case (Matrix.RP_CONS(pathVar,first,second),localCache,localEnv,localDfaEnv)
      local
        Absyn.Ident pathVar;
        Matrix.RenamedPat first,second;
        list<Absyn.ElementItem> elem1,elem2;
        Absyn.Ident firstPathVar,secondPathVar;
        Absyn.TypeSpec t;
        list<Absyn.AlgorithmItem> assignList;
        Absyn.AlgorithmItem assign1,assign2;  
        list<tuple<Absyn.Ident,Absyn.TypeSpec>> dfaEnvElem1,dfaEnvElem2;
      equation
        //Example:
        // if (pathVar = CONS)    -- (This comparison will not occure)
        // TYPE1 pathVar__1; 
        // list<TYPE1> pathVar__2;
        // pathVar__1 = car(x);
        // pathVar__2 = cdr(x);
        
        // The variable should be found in the DFA environment
        Absyn.TCOMPLEX(Absyn.IDENT("list"),{t},NONE()) = lookupTypeOfVar(localDfaEnv,pathVar); 
        
        firstPathVar = extractPathVar(first);  
        elem1 = {Absyn.ELEMENTITEM(Absyn.ELEMENT(
          false,NONE(),Absyn.UNSPECIFIED(),"component",
          Absyn.COMPONENTS(Absyn.ATTR(false,Absyn.VAR(),Absyn.BIDIR(),{}),
            t,		
            {Absyn.COMPONENTITEM(Absyn.COMPONENT(firstPathVar,{},NONE()),NONE(),NONE())}),
            Absyn.INFO("f",false,0,0,0,0),NONE()))};

        secondPathVar = extractPathVar(second);
        elem2 = {Absyn.ELEMENTITEM(Absyn.ELEMENT(
          false,NONE(),Absyn.UNSPECIFIED(),"component",
          Absyn.COMPONENTS(Absyn.ATTR(false,Absyn.VAR(),Absyn.BIDIR(),{}),
            Absyn.TCOMPLEX(Absyn.IDENT("list"),{t},NONE()),		
            {Absyn.COMPONENTITEM(Absyn.COMPONENT(secondPathVar,{},NONE()),NONE(),NONE())}),
            Absyn.INFO("f",false,0,0,0,0),NONE()))};
        
        // Add the new variables to the DFA environment
        // For example, if we have a pattern:
        // RP_CONS(x,RP_INTEGER(x__1,1),RP_CONS(x__2,RP_INTEGER(x__2__1,2),RP_EMPTYLIST(x__2__2)))
        // Then we must know the type of x__2 when arriving to the second
        // RP_CONS pattern
        dfaEnvElem1 = {(firstPathVar,t)}; 
        dfaEnvElem2 = {(secondPathVar,Absyn.TCOMPLEX(Absyn.IDENT("list"),{t},NONE()))};
        localDfaEnv = listAppend(localDfaEnv,dfaEnvElem1); 
        localDfaEnv = listAppend(localDfaEnv,dfaEnvElem2);
        elem1 = listAppend(elem1,elem2);
        
       /* assign1 = Absyn.ALGORITHMITEM(Absyn.ALG_ASSIGN(Absyn.CREF(Absyn.CREF_IDENT(firstPathVar,{})),
          Absyn.CALL(Absyn.CREF_IDENT("car",{}),Absyn.FUNCTIONARGS({Absyn.CREF(Absyn.CREF_IDENT(pathVar,{}))},{}))),NONE());
        assign2 = Absyn.ALGORITHMITEM(Absyn.ALG_ASSIGN(Absyn.CREF(Absyn.CREF_IDENT(secondPathVar,{})),
          Absyn.CALL(Absyn.CREF_IDENT("cdr",{}),Absyn.FUNCTIONARGS({Absyn.CREF(Absyn.CREF_IDENT(pathVar,{}))},{}))),NONE());
				*/
        assignList = {}; //listAppend({assign1},{assign2}); 
      then (localCache,localDfaEnv,elem1,assignList);
    case (Matrix.RP_CALL(pathVar,Absyn.CREF_IDENT(recName,_),argList),localCache,localEnv,localDfaEnv)
      local
        Absyn.Ident pathVar,recName;
        list<Absyn.Ident> pathVarList,fieldNameList;
        list<Matrix.RenamedPat> argList;
        SCode.Class sClass;
        list<Absyn.TypeSpec> fieldTypes; 
        Absyn.Path pathName;
        list<Absyn.ElementItem> elemList;
        list<Absyn.AlgorithmItem> assignList; 
        list<tuple<Absyn.Ident,Absyn.TypeSpec>> dfaEnvElem;
      equation
        // For instance if we have 
        // a record RECNAME{ TYPE1 field1, TYPE2 field2 } :
        // 
        // if (getType(pathVar) = RECNAME)
        // TYPE1 pathVar__1; 
        // TYPE2 pathVar__2;
        // x__1 = pathVar.field1;
        // x__2 = pathVar.field2;
        
        pathVarList = Util.listMap(argList,extractPathVar);
        // Get recordnames
        pathName = Absyn.IDENT(recName);
        (localCache,sClass,localEnv) = Lookup.lookupClass(localCache,localEnv,pathName,true);
        (fieldNameList,fieldTypes) = extractFieldNamesAndTypes(sClass);
        
        dfaEnvElem = mergeLists(pathVarList,fieldTypes,{});
        localDfaEnv = listAppend(localDfaEnv,dfaEnvElem);
        
        assignList = createPathVarAssignments(pathVar,pathVarList,fieldNameList,{});
        elemList = createPathVarDeclarations(pathVarList,fieldNameList,fieldTypes,{});
      then (localCache,localDfaEnv,elemList,assignList);	
   /* case (Matrix.RP_TUPLE(lst))	  */
  end matchcontinue;
end generatePathVarDeclarations;


public function extractFieldNamesAndTypes "function: extractFieldNamesAndTypes
	author: KS
"
  input SCode.Class sClass;
  output list<Absyn.Ident> fieldNameList;
  output list<Absyn.TypeSpec> fieldTypes;  
algorithm
  (fieldNameList,fieldTypes) :=
  matchcontinue (sClass)
    case (SCode.CLASS(_,_,_,_,SCode.PARTS(elemList,_,_,_,_,_)))
      local
        list<Absyn.Ident> fNameList;
        list<Absyn.TypeSpec> fTypes;
        list<SCode.Element> elemList;  
      equation
        fNameList = Util.listMap(elemList,extractFieldName);
        fTypes = Util.listMap(elemList,extractFieldType);  
      then (fNameList,fTypes);
  end matchcontinue;    
end extractFieldNamesAndTypes;  


public function extractFieldName "function: extractFieldName
	author: KS
"
  input SCode.Element elem;
  output Absyn.Ident id;  
algorithm
  id :=
  matchcontinue (elem)
    case (SCode.COMPONENT(localId,_,_,_,_,_,_,_,_,_))
      local
        Absyn.Ident localId;
      equation
      then localId;
  end matchcontinue;  
end extractFieldName;


public function extractFieldType "function: extractFieldType
	author: KS
"
  input SCode.Element elem;
  output Absyn.TypeSpec typeSpec;  
algorithm
  typeSpec :=
  matchcontinue (elem)
    case (SCode.COMPONENT(_,_,_,_,_,_,t,_,_,_))
      local
        Absyn.TypeSpec t;
      equation
      then t;
  end matchcontinue;  
end extractFieldType;


protected function createPathVarDeclarations "function: createPathVarAssignments
	author: KS
	Used when we have a record constructor call in a pattern and we need to
	create path variables of the subpatterns of the record constructor.
"
  input list<Absyn.Ident> pathVars;  
  input list<Absyn.Ident> recFieldNames;
  input list<Absyn.TypeSpec> recTypes;
  input list<Absyn.ElementItem> accElemList;
  output list<Absyn.ElementItem> elemList;
algorithm
  elemList :=
  matchcontinue (pathVars,recFieldNames,recTypes,accElemList)
    case ({},{},{},localAccElemList) 
      local
        list<Absyn.ElementItem> localAccElemList;
      equation
    then localAccElemList;
    case (firstPathVar :: restPathVars,firstFieldVar :: restFieldVars,
          firstType :: restTypes,localAccElemList)  
      local
        list<Absyn.ElementItem> elem,localAccElemList;
        Absyn.Ident localRecName,firstPathVar,firstFieldVar;
        list<Absyn.Ident> restPathVars,restFieldVars;
        Absyn.TypeSpec firstType;
        list<Absyn.TypeSpec> restTypes;  
      equation

        elem = {Absyn.ELEMENTITEM(Absyn.ELEMENT(
          false,NONE(),Absyn.UNSPECIFIED(),"component",
          Absyn.COMPONENTS(Absyn.ATTR(false,Absyn.VAR(),Absyn.BIDIR(),{}),
            firstType,		
            {Absyn.COMPONENTITEM(Absyn.COMPONENT(firstPathVar,{},NONE())
            ,NONE(),NONE())}),
            Absyn.INFO("f",false,0,0,0,0),NONE()))};
            
        localAccElemList = listAppend(localAccElemList,elem);
        localAccElemList = createPathVarDeclarations(restPathVars,
          restFieldVars,restTypes,localAccElemList);  
    then localAccElemList;
  end matchcontinue;   
end createPathVarDeclarations;  


protected function createPathVarAssignments "function: createPathVarAssignments
	author: KS
	Used when we have a record constructor call in a pattern and need to
	bind the path variables of the subpatterns of the record constructor
	to values.
"
  input Absyn.Ident recVarName;
  input list<Absyn.Ident> pathVarList;
  input list<Absyn.Ident> fieldNameList;
  input list<Absyn.AlgorithmItem> accList;
  output list<Absyn.AlgorithmItem> outList;
algorithm
  outList :=
  matchcontinue (recVarName,pathVarList,fieldNameList,accList)
    local
    list<Absyn.AlgorithmItem> localAccList;
    case (_,{},{},localAccList) then localAccList;
    case (localRecVarName,firstPathVar :: restVar,firstFieldName :: restFieldNames,
        localAccList)
      local
        Absyn.Ident localRecVarName,firstPathVar,firstFieldName;
        list<Absyn.Ident> restVar,restFieldNames;
        list<Absyn.AlgorithmItem> elem;     
      equation
        elem = {Absyn.ALGORITHMITEM(Absyn.ALG_ASSIGN(
          Absyn.CREF(Absyn.CREF_IDENT(firstPathVar,{})),
          Absyn.CREF(Absyn.CREF_QUAL(localRecVarName,{},
          Absyn.CREF_IDENT(firstFieldName,{})))),NONE())};

        localAccList = listAppend(localAccList,elem);
        localAccList = createPathVarAssignments(localRecVarName,restVar,restFieldNames,localAccList);        
      then localAccList;
  end matchcontinue;
end createPathVarAssignments;
  

protected function generateIfElseifAndElse "function: generateIfElseifAndElse
	author: KS
	Generate if-statements.
"
  input list<Arc> arcs;
  input Absyn.Ident stateVar;
  input Boolean ifOrNotBool;
  input Absyn.Exp trueStatement;
  input list<Absyn.AlgorithmItem> trueBranch;
  input list<tuple<Absyn.Exp, list<Absyn.AlgorithmItem>>> elseIfBranch;
  input Env.Cache cache;
  input Env.Env env; 
  input list<tuple<Absyn.Ident,Absyn.TypeSpec>> dfaEnv; 
  input list<Absyn.ElementItem> accNewVars;
  output Env.Cache outCache;
  output list<Absyn.AlgorithmItem> outList;  
  output list<Absyn.ElementItem> outNewVars;
algorithm
  (outCache,outList,outNewVars) :=
  matchcontinue (arcs,stateVar,ifOrNotBool,trueStatement,trueBranch,elseIfBranch,cache,env,dfaEnv,accNewVars)
    local
      State localState;
      list<Arc> rest;
      Absyn.Ident localStateVar;
      Matrix.RenamedPat pat;
      Absyn.Exp localTrueStatement,branchCheck;
      list<Absyn.AlgorithmItem> localTrueBranch,localElseBranch,algList;
      list<Absyn.Exp,list<Absyn.AlgorithmItem>> localElseIfBranch;
      Env.Cache localCache;
      Env.Env localEnv; 
      list<tuple<Absyn.Ident,Absyn.TypeSpec>> localDfaEnv;
      tuple<Absyn.Exp,list<Absyn.AlgorithmItem>> tup;
      Integer localRetExpLen;
      list<Integer> caseNumbers; 
      list<Absyn.ElementItem> localAccNewVars;
    case({},_,_,localTrueStatement,localTrueBranch,localElseIfBranch,localCache,_,_,localAccNewVars)
      local 
      equation 
        algList = {Absyn.ALGORITHMITEM(Absyn.ALG_IF(localTrueStatement,localTrueBranch,localElseIfBranch,{}),NONE())};
      then (localCache,algList,localAccNewVars);
        
        // DummieState    
    case(ARC(DUMMIESTATE(),_,_,_) :: _,_,_,localTrueStatement,localTrueBranch,localElseIfBranch,localCache,_,_,localAccNewVars) 
      equation
        //print("DUMMIE STATE\n");
        algList = {Absyn.ALGORITHMITEM(Absyn.ALG_IF(localTrueStatement,localTrueBranch,localElseIfBranch,{}),NONE())};
      then (localCache,algList,localAccNewVars);
        
        // Else case   
    case(ARC(localState,_,NONE(),caseNumbers) :: _,localStateVar,_,localTrueStatement,localTrueBranch,localElseIfBranch,localCache,localEnv,localDfaEnv,localAccNewVars)
      local 
        list<Absyn.Exp,list<Absyn.AlgorithmItem>> eIfBranch;
      equation
        // For the catch handling 
        branchCheck = generateBranchCheck(caseNumbers,Absyn.BOOL(false));
        
        (localCache,localElseBranch,localAccNewVars) = fromStatetoAbsynCode(localState,NONE(),localCache,localEnv,localDfaEnv,localAccNewVars);
        eIfBranch = {(branchCheck,localElseBranch)};
        localElseIfBranch = listAppend(localElseIfBranch,eIfBranch);
        algList = {Absyn.ALGORITHMITEM(Absyn.ALG_IF(localTrueStatement,localTrueBranch,localElseIfBranch,{}),NONE())};  
      then (localCache,algList,localAccNewVars);
        
        //If, Wildcard case
    case(ARC(localState,_,SOME(pat as Matrix.RP_WILDCARD(_)),caseNumbers) :: rest,localStateVar,true,_,_,_,localCache,localEnv,localDfaEnv,localAccNewVars)
      equation
        (localCache,localTrueBranch,localAccNewVars) = fromStatetoAbsynCode(localState,SOME(pat),localCache,localEnv,localDfaEnv,localAccNewVars);
        branchCheck = generateBranchCheck(caseNumbers,Absyn.BOOL(false));
        (localCache,algList,localAccNewVars) = generateIfElseifAndElse(rest,localStateVar,false,branchCheck,localTrueBranch,{},localCache,localEnv,localDfaEnv,localAccNewVars);
      then (localCache,algList,localAccNewVars);
        
        //If, Cons case
    case(ARC(localState,_,SOME(pat as Matrix.RP_CONS(_,_,_)),caseNumbers) :: rest,localStateVar,true,_,_,_,localCache,localEnv,localDfaEnv,localAccNewVars)
      local
        Absyn.Exp exp;
      equation
        (localCache,localTrueBranch,localAccNewVars) = fromStatetoAbsynCode(localState,SOME(pat),localCache,localEnv,localDfaEnv,localAccNewVars);
        branchCheck = generateBranchCheck(caseNumbers,Absyn.BOOL(false));
       //Absyn.LBINARY( Absyn.AND(),Absyn.LUNARY(Absyn.NOT(),Absyn.CALL(Absyn.CREF_IDENT("emptyList",{}),
        //  Absyn.FUNCTIONARGS({Absyn.CREF(Absyn.CREF_IDENT(localStateVar,{}))},{})))); 
        (localCache,algList,localAccNewVars) = generateIfElseifAndElse(rest,localStateVar,false,branchCheck,localTrueBranch,{},localCache,localEnv,localDfaEnv,localAccNewVars);
      then (localCache,algList,localAccNewVars);
        
        //If, CONSTANT
    case(ARC(localState,_,SOME(pat),caseNumbers) :: rest,localStateVar,true,_,_,_,localCache,localEnv,localDfaEnv,localAccNewVars)
      local
        Absyn.Exp exp,constVal,firstExp;
      equation
        
        (localCache,localTrueBranch,localAccNewVars) = fromStatetoAbsynCode(localState,SOME(pat),localCache,localEnv,localDfaEnv,localAccNewVars);
        constVal = getConstantValue(pat);
        firstExp = createConstCompareExp(constVal,localStateVar);
        branchCheck = generateBranchCheck(caseNumbers,Absyn.BOOL(false));    
        exp = Absyn.LBINARY(firstExp,Absyn.AND(),branchCheck);
        (localCache,algList,localAccNewVars) = generateIfElseifAndElse(rest,localStateVar,false,exp,localTrueBranch,{},localCache,localEnv,localDfaEnv,localAccNewVars);
      then (localCache,algList,localAccNewVars);
              
        //If, CALL case
    case(ARC(localState,_,SOME(pat as Matrix.RP_CALL(_,Absyn.CREF_IDENT(recordName,_),_)),caseNumbers) :: rest,localStateVar,true,_,_,_,  
        localCache,localEnv,localDfaEnv,localAccNewVars)
      local
        Absyn.Exp exp;
        Absyn.Ident recordName;
        list<Absyn.Exp> tempList;
      equation
        (localCache,localTrueBranch,localAccNewVars) = fromStatetoAbsynCode(localState,SOME(pat),localCache,localEnv,localDfaEnv,localAccNewVars);
        branchCheck = generateBranchCheck(caseNumbers,Absyn.BOOL(false));          
        tempList = {Absyn.CREF(Absyn.CREF_IDENT(localStateVar,{}))};
        exp = Absyn.LBINARY(Absyn.CALL(Absyn.CREF_IDENT("stringCmp",{}),Absyn.FUNCTIONARGS({Absyn.CREF(Absyn.CREF_QUAL(localStateVar,{},Absyn.CREF_IDENT("fieldTag__",{})))    
          ,Absyn.STRING(recordName)},{})),Absyn.AND(),branchCheck);
        (localCache,algList,localAccNewVars) = generateIfElseifAndElse(rest,localStateVar,false,exp,localTrueBranch,{},localCache,localEnv,localDfaEnv,localAccNewVars);  
        
      then (localCache,algList,localAccNewVars); 
        //Elseif, wildcard
    case(ARC(localState,_,SOME(pat as Matrix.RP_WILDCARD(_)),caseNumbers) :: rest,localStateVar,false,localTrueStatement,
        localTrueBranch,localElseIfBranch,localCache,localEnv,localDfaEnv,localAccNewVars)
      local
        list<Absyn.AlgorithmItem> eIfBranch;
        Absyn.Exp exp;
      equation
        (localCache,eIfBranch,localAccNewVars) = fromStatetoAbsynCode(localState,SOME(pat),localCache,localEnv,localDfaEnv,localAccNewVars);
        branchCheck = generateBranchCheck(caseNumbers,Absyn.BOOL(false));
        tup = (branchCheck,eIfBranch);
        localElseIfBranch = listAppend(localElseIfBranch,{tup});
        (localCache,algList,localAccNewVars) = generateIfElseifAndElse(rest,localStateVar,false,localTrueStatement,localTrueBranch,localElseIfBranch,localCache,localEnv,localDfaEnv,localAccNewVars);
      then (localCache,algList,localAccNewVars);
        
        //Elseif, cons
    case(ARC(localState,_,SOME(pat as Matrix.RP_CONS(_,_,_)),caseNumbers) :: rest,localStateVar,false,localTrueStatement,
        localTrueBranch,localElseIfBranch,localCache,localEnv,localDfaEnv,localAccNewVars)
      local
        list<Absyn.AlgorithmItem> eIfBranch;
        Absyn.Exp exp;
      equation
        (localCache,eIfBranch,localAccNewVars) = fromStatetoAbsynCode(localState,SOME(pat),localCache,localEnv,localDfaEnv,localAccNewVars);
        branchCheck = generateBranchCheck(caseNumbers,Absyn.BOOL(false));
          //Absyn.LBINARY(Absyn.AND(),Absyn.LUNARY(Absyn.NOT(),Absyn.CALL(Absyn.CREF_IDENT("emptyList",{}),
          //  Absyn.FUNCTIONARGS({Absyn.CREF(Absyn.CREF_IDENT(localStateVar,{}))},{}))));    
        tup = (branchCheck,eIfBranch);
        localElseIfBranch = listAppend(localElseIfBranch,{tup});
        (localCache,algList,localAccNewVars) = generateIfElseifAndElse(rest,localStateVar,false,localTrueStatement,localTrueBranch,localElseIfBranch,localCache,localEnv,localDfaEnv,localAccNewVars);
      then (localCache,algList,localAccNewVars);
          
          //Elseif, call
    case(ARC(localState,_,SOME(pat as Matrix.RP_CALL(_,Absyn.CREF_IDENT(recordName,_),_)),caseNumbers) :: rest,localStateVar,false,localTrueStatement,
        localTrueBranch,localElseIfBranch,localCache,localEnv,localDfaEnv,localAccNewVars)
      local
        list<Absyn.AlgorithmItem> eIfBranch;
        list<Absyn.Exp> tempList;
        Absyn.Exp exp;
        Absyn.Ident recordName;
      equation
        (localCache,eIfBranch,localAccNewVars) = fromStatetoAbsynCode(localState,SOME(pat),localCache,localEnv,localDfaEnv,localAccNewVars);
        tempList = {Absyn.CREF(Absyn.CREF_IDENT(localStateVar,{}))};
        branchCheck = generateBranchCheck(caseNumbers,Absyn.BOOL(false));
        exp = Absyn.LBINARY(Absyn.CALL(Absyn.CREF_IDENT("stringCmp",{}),Absyn.FUNCTIONARGS({Absyn.CREF(Absyn.CREF_QUAL(localStateVar,{},Absyn.CREF_IDENT("fieldTag__",{}))),
          Absyn.STRING(recordName)},{})),Absyn.AND(),branchCheck);
        tup = (exp,eIfBranch);
        localElseIfBranch = listAppend(localElseIfBranch,{tup});
        (localCache,algList,localAccNewVars) = generateIfElseifAndElse(rest,localStateVar,false,localTrueStatement,localTrueBranch,localElseIfBranch,localCache,localEnv,localDfaEnv,localAccNewVars);
      then (localCache,algList,localAccNewVars);
          
        //Elseif, constant
    case(ARC(localState,_,SOME(pat),caseNumbers) :: rest,localStateVar,false,localTrueStatement,
        localTrueBranch,localElseIfBranch,localCache,localEnv,localDfaEnv,localAccNewVars)
      local
        list<Absyn.AlgorithmItem> eIfBranch;
        Absyn.Exp exp,constVal,firstExp;
      equation        
        constVal = getConstantValue(pat);
        (localCache,eIfBranch,localAccNewVars) = fromStatetoAbsynCode(localState,SOME(pat),localCache,localEnv,localDfaEnv,localAccNewVars);
        firstExp = createConstCompareExp(constVal,localStateVar);
        branchCheck = generateBranchCheck(caseNumbers,Absyn.BOOL(false));
        exp = Absyn.LBINARY(firstExp,Absyn.AND(),branchCheck);
        tup = (exp,eIfBranch);
        localElseIfBranch = listAppend(localElseIfBranch,{tup});
        (localCache,algList,localAccNewVars) = generateIfElseifAndElse(rest,localStateVar,false,localTrueStatement,localTrueBranch,localElseIfBranch,localCache,localEnv,localDfaEnv,localAccNewVars);
      then (localCache,algList,localAccNewVars); 
  end matchcontinue;    
end generateIfElseifAndElse;

protected function generateBranchCheck "function: generateBranchCheck"
  input list<Integer> inList; 
  input Absyn.Exp inExp; 
  output Absyn.Exp outExp;   
algorithm   
  outExp := 
  matchcontinue (inList,inExp) 
    local
      Absyn.Exp localInExp; 
    case (_,Absyn.BOOL(false)) 
      local 
      equation 
        localInExp = Absyn.BOOL(true); 
      then localInExp;  
    case ({},localInExp) then localInExp;
      
    case (firstNum :: restNum,localInExp)   
      local 
        Integer firstNum;
        list<Integer> restNum; 
      equation
        localInExp = Absyn.LBINARY(localInExp,Absyn.OR(),
          Absyn.CREF(Absyn.CREF_IDENT("BOOLVAR__",{Absyn.SUBSCRIPT(Absyn.INTEGER(firstNum))}))); 
        localInExp = generateBranchCheck(restNum,localInExp);
      then localInExp;    
  end matchcontinue;   
end generateBranchCheck;  

protected function createConstCompareExp "function: createConstCompareExp
Used by generateIfElseifAndElse
when we want two write an expression for comparing constants
"
  input Absyn.Exp constVal;
  input Absyn.Ident stateVar;  
  output Absyn.Exp outExp;  
algorithm  
  outExp :=
  matchcontinue (constVal,stateVar)
    local
      Integer i;
      Real r;
      String s;
      Boolean b;  
      Absyn.Exp exp;
      Absyn.Ident localStateVar;
    case (Absyn.INTEGER(i),localStateVar)
      equation
      exp = Absyn.RELATION(Absyn.CREF(Absyn.CREF_IDENT(localStateVar,{})),
        Absyn.EQUAL(),Absyn.INTEGER(i));
      then exp;  
    case (Absyn.REAL(r),localStateVar)
      equation
        exp = Absyn.RELATION(Absyn.CALL(Absyn.CREF_IDENT("String",{}),
          Absyn.FUNCTIONARGS({Absyn.REAL(r),Absyn.INTEGER(5)},{})),
            Absyn.EQUAL(),Absyn.CALL(Absyn.CREF_IDENT("String",{}),
          Absyn.FUNCTIONARGS({Absyn.CREF(Absyn.CREF_IDENT(localStateVar,{})),Absyn.INTEGER(5)},{})));
      then exp;  
    case (Absyn.STRING(s),localStateVar)
      equation
        exp = Absyn.RELATION(Absyn.STRING(s),Absyn.EQUAL(),Absyn.CREF(Absyn.CREF_IDENT(localStateVar,{})));
      then exp;
    case (Absyn.BOOL(b),localStateVar)
      equation
        exp = Absyn.RELATION(Absyn.CREF(Absyn.CREF_IDENT(localStateVar,{})),
          Absyn.EQUAL(),Absyn.BOOL(b));
      then exp;  
    case (Absyn.LIST({}),localStateVar)
      equation
        exp = Absyn.BOOL(true); //Absyn.CALL(Absyn.CREF_IDENT("emptyList",{}),
          //Absyn.FUNCTIONARGS({Absyn.CREF(Absyn.CREF_IDENT(localStateVar,{}))},{}));
      then exp;      
 end matchcontinue;   
end createConstCompareExp;  


protected function fromEquationsToAlgAssignments "function: fromEquationsToAlgAssignments
 Convert equations to algorithm assignments"
  input list<Absyn.EquationItem> eqsIn;
  input list<Absyn.AlgorithmItem> accList;
  output list<Absyn.AlgorithmItem> algsOut;
algorithm
  algOut :=
  matchcontinue (eqsIn,accList)
    local
      list<Absyn.AlgorithmItem> localAccList;  
    case ({},localAccList) equation then localAccList;
    case (Absyn.EQUATIONITEM(first,_) :: rest,localAccList)      
      local
        Absyn.Equation first;
        list<Absyn.EquationItem> rest;
        Absyn.AlgorithmItem firstAlg;
        list<Absyn.AlgorithmItem> restAlgs;
      equation    
        firstAlg = fromEquationToAlgAssignment(first);
        localAccList = listAppend(localAccList,{firstAlg});
        restAlgs = fromEquationsToAlgAssignments(rest,localAccList);    
      then restAlgs;  
  end matchcontinue;
end fromEquationsToAlgAssignments;

protected function fromEquationToAlgAssignment "function: fromEquationToAlgAssignment"
  input Absyn.Equation eq;
  output Absyn.AlgorithmItem algStatement;
algorithm
  algStatement :=
  matchcontinue (eq)
    case (Absyn.EQ_EQUALS(left,right))    
      local
        Absyn.Exp left,right;
        Absyn.AlgorithmItem algItem;
      equation
        algItem = Absyn.ALGORITHMITEM(Absyn.ALG_ASSIGN(left,right),NONE());  	
      then algItem;
  end matchcontinue;
end fromEquationToAlgAssignment;

protected function createListFromExpression "function: createListFromExpression"
  input Absyn.Exp exp;
  output list<Absyn.Exp> outList;
algorithm
  outList :=
  matchcontinue (exp)
    local
      list<Absyn.Exp> l;  
      Absyn.Exp e;
    case(Absyn.TUPLE(l)) then l;
    case (e) 
      equation 
        l = {e}; 
      then l;
  end matchcontinue;
end createListFromExpression;

public function boolString "function:: boolString"
  input Boolean bool;
  output String str;
algorithm
  str :=
  matchcontinue (bool)
    case (true) equation then "true";
    case (false) equation then "false";
  end matchcontinue;       
end boolString;

protected function getConstantValue "function: getConstantValue"
  input Matrix.RenamedPat pat;
  output Absyn.Exp val;
algorithm
  val :=
  matchcontinue (pat)
    case (Matrix.RP_INTEGER(_,val))
      local
        Integer val;
      equation
      then Absyn.INTEGER(val); 
    case (Matrix.RP_STRING(_,val))
      local
        String val;
      equation
      then Absyn.STRING(val);
    case (Matrix.RP_BOOL(_,val))
      local
        Boolean val;
      equation
      then Absyn.BOOL(val);
    case (Matrix.RP_REAL(_,val))
      local
        Real val;
      equation
      then Absyn.REAL(val);  
    case (Matrix.RP_EMPTYLIST(_))
      then Absyn.LIST({});           
  end matchcontinue;  
end getConstantValue;

public function extractPathVar "function: extractPathVar"
  input Matrix.RenamedPat pat;
  output Absyn.Ident pathVar;
algorithm
  pathVar :=
  matchcontinue (pat)
    local
      Absyn.Ident localPathVar;
    case (Matrix.RP_INTEGER(localPathVar,_)) equation then localPathVar;
    case (Matrix.RP_REAL(localPathVar,_)) equation then localPathVar;
    case (Matrix.RP_BOOL(localPathVar,_)) equation then localPathVar;
    case (Matrix.RP_STRING(localPathVar,_)) equation then localPathVar;
    case (Matrix.RP_CONS(localPathVar,_,_)) equation then localPathVar;
    case (Matrix.RP_CALL(localPathVar,_,_)) equation then localPathVar;
    case (Matrix.RP_TUPLE(localPathVar,_)) equation then localPathVar;
    case (Matrix.RP_WILDCARD(localPathVar)) equation then localPathVar;    
    case (Matrix.RP_EMPTYLIST(localPathVar)) equation then localPathVar;     
  end matchcontinue;    
end extractPathVar;

protected function constructorOrNot "function: constructorOrNot"
  input Matrix.RenamedPat pat;
  output Boolean val;
algorithm
  val :=
  matchcontinue (pat)
    case (Matrix.RP_CONS(_,_,_))
      equation
      then true;
    case (Matrix.RP_TUPLE(_,_))
      equation
      then true;
    case (Matrix.RP_CALL(_,_,_))
      equation
      then true;
    case (_)
      equation
      then false;
  end matchcontinue;    
end constructorOrNot;


protected function typeConvert "function: typeConvert"
  input Types.TType t;
  output Absyn.TypeSpec outType;
algorithm
  outType := 
  matchcontinue (t)
    case (Types.T_INTEGER(_)) then Absyn.TPATH(Absyn.IDENT("Integer"),NONE());
    case (Types.T_BOOL(_)) then Absyn.TPATH(Absyn.IDENT("Boolean"),NONE());
    case (Types.T_STRING(_)) then Absyn.TPATH(Absyn.IDENT("String"),NONE());
    case (Types.T_REAL(_)) then Absyn.TPATH(Absyn.IDENT("Real"),NONE()); 
    case (Types.T_COMPLEX(ClassInf.RECORD(s), _, _)) local String s; 
      equation
      then Absyn.TPATH(Absyn.IDENT(s),NONE()); 
    case (Types.T_LIST((t,_)))  
      local 
        Absyn.TypeSpec tSpec; 
        Types.TType t;  
        list<Absyn.TypeSpec> tSpecList; 
      equation
        tSpec = typeConvert(t);
        tSpecList = {tSpec};
      then Absyn.TCOMPLEX(Absyn.IDENT("list"),tSpecList,NONE());      
    // ...
  end matchcontinue;  
end typeConvert;

protected function lookupTypeOfVar "function: lookupTypeOfVar"
  input list<tuple<Absyn.Ident,Absyn.TypeSpec>> dfaEnv;  
  input Absyn.Ident id;  
  output Absyn.TypeSpec outTypeSpec;  
algorithm
  outTypeSpec :=  
  matchcontinue (dfaEnv,id)  
    case ({},_) then fail(); 
    case ((localId2,t2) :: restTups,localId) 
      local 
        Absyn.TypeSpec t2;
        list<tuple<Absyn.Ident,Absyn.TypeSpec>> restTups; 
        Absyn.Ident localId,localId2;
      equation
        true = (localId ==& localId2);
      then t2;  
    case (_ :: restTups,localId) 
      local  
        Absyn.TypeSpec t;
        list<tuple<Absyn.Ident,Absyn.TypeSpec>> restTups; 
        Absyn.Ident localId;
      equation 
        t = lookupTypeOfVar(restTups,localId);
      then t;
  end matchcontinue;
end lookupTypeOfVar;    

protected function mergeLists "function: mergeLists" 
  input list<Absyn.Ident> idList;   
  input list<Absyn.TypeSpec> tList; 
  input list<tuple<Absyn.Ident,Absyn.TypeSpec>> accList;
  output list<tuple<Absyn.Ident,Absyn.TypeSpec>> outList;  
algorithm
  outTypeSpec :=  
  matchcontinue (idList,tList,accList)   
    local 
      list<tuple<Absyn.Ident,Absyn.TypeSpec>> localAccList;
    case ({},_,localAccList) then localAccList; // Should not happen  
    case (_,{},localAccList) then localAccList; // Should not happen 
    case (id :: restIds,tSpec :: restSpecs,localAccList) 
      local  
        Absyn.Ident id; 
        list<Absyn.Ident> restIds; 
        list<Absyn.TypeSpec> restSpecs;
        Absyn.TypeSpec tSpec;
      equation  
        localAccList = listAppend(localAccList,{(id,tSpec)});
      then localAccList;       
  end matchcontinue;
end mergeLists;  

protected function addVarsToDfaEnv "function: addVarsToDfaEnv"
  input list<Absyn.Exp> expList; 
  input list<tuple<Absyn.Ident,Absyn.TypeSpec>> dfaEnv;
  input Env.Cache cache;  
  input Env.Env env; 
  output list<tuple<Absyn.Ident,Absyn.TypeSpec>> outDfaEnv;
  output Env.Cache outCache; 
algorithm  
  (outDfaEnv,outCache) :=
  matchcontinue (expList,dfaEnv,cache,env)   
    local
      list<tuple<Absyn.Ident,Absyn.TypeSpec>> localDfaEnv; 
      Env.Cache localCache;  
      Env.Env localEnv;
    case ({},localDfaEnv,localCache,_) then (localDfaEnv,localCache);  
    case (Absyn.CREF(Absyn.CREF_IDENT(firstId,{})) :: restExps,localDfaEnv,localCache,localEnv)  
      local
        Absyn.Ident firstId;  
        Types.TType t;
        Absyn.TypeSpec t2; 
        list<tuple<Absyn.Ident,Absyn.TypeSpec>> dfaEnvElem; 
        list<Absyn.Exp> restExps;
      equation  
        (localCache,Types.VAR(_,_,_,(t,_),_),_,_) = Lookup.lookupIdent(localCache,localEnv,firstId);
        t2 = typeConvert(t);
        dfaEnvElem = {(firstId,t2)};
        localDfaEnv = listAppend(localDfaEnv,dfaEnvElem); 
        (localDfaEnv,localCache) = addVarsToDfaEnv(restExps,localDfaEnv,localCache,localEnv);
      then (localDfaEnv,localCache);
    case (_,_,_,_) then fail(); 
  end matchcontinue;
end addVarsToDfaEnv;   

protected function createListOfTrue "function: createListOfTrue"
  input Integer nStates;  
  input list<Absyn.Exp> accList; 
  output list<Absyn.Exp> outList;   
algorithm
  outList :=   
  matchcontinue (nStates,accList)  
    local  
      list<Absyn.Exp> localAccList;
    case (0,localAccList) then localAccList;  
    case (n,localAccList) 
      local
        Integer n;     
        list<Absyn.Exp> e; 
      equation  
        e = {Absyn.BOOL(true)};
        localAccList = listAppend(localAccList,e);
        localAccList = createListOfTrue(n-1,localAccList);
      then localAccList; 
  end matchcontinue;
end createListOfTrue;  

public function addNewSimpleState "function: addNewSimpleState"
  input list<SimpleState> stateList; 
  input Integer stateNum; 
  input SimpleState state; 
  output list<SimpleState> outList; 
algorithm 
  outList := 
  matchcontinue (stateList,stateNum,state)
    case (localStateList,localStateNum,localState) 
      local 
        SimpleStateArray localStateArray; 
        Integer localStateNum; 
        SimpleState localState; 
        list<SimpleState> localStateList;
      equation
        false = (localStateNum > listLength(localStateList)); 
        localStateArray = listArray(localStateList);
        localStateArray = arrayUpdate(localStateArray,localStateNum,localState);
        localStateList = arrayList(localStateArray);
      then localStateList;
    case (localStateList,localStateNum,localState) 
      local 
        Integer n; 
        Integer localStateNum; 
        SimpleState localState; 
        list<SimpleState> localStateList;
      equation  
        n = listLength(localStateList);
        localStateList = increaseListSize(localStateList,localStateNum - n);
        localStateList = addNewSimpleState(localStateList,localStateNum,localState);
      then localStateList; 
  end matchcontinue;
end addNewSimpleState;

protected function increaseListSize "function: increaseListSize"
  input list<SimpleState> inList; 
  input Integer size; 
  output list<SimpleState> outList; 
algorithm   
  outList := 
  matchcontinue (inList,size) 
    local 
      list<SimpleState> localInList;      
    case (localInList,0) then localInList; 
    case (localInList,n) 
      local 
        Integer n;      
      equation
        localInList = listAppend(localInList,{SIMPLEDUMMIE()});
        localInList = increaseListSize(localInList,n-1);
      then localInList; 
  end matchcontinue;
end increaseListSize;

public function simplifyState "function: simplifyState
Transform a normal state into a simple, 'light' state.
"
  input State normalState; 
  output SimpleState simpleState; 
algorithm
  simpleState :=  
  matchcontinue (normalState)
    case (STATE(n,_,arcs as (ARC(_,_,SOME(p),_) :: _),NONE())) 
      local 
        Integer n; 
        list<Arc> arcs;  
        Absyn.Ident varName; 
        Matrix.RenamedPat p; 
        list<ArcName,Stamp> simpleArcs; 
        SimpleState sState;
      equation
        varName = extractPathVar(p);
        simpleArcs = simplifyArcs(arcs,{});
        sState = SIMPLESTATE(n,simpleArcs,0,SOME(varName)); 
      then sState;
    case (_) 
    then fail(); 
  end matchcontinue;
end simplifyState; 

public function simplifyArcs "function: simplifyArcs" 
  input list<Arc> inArcs; 
  input  list<ArcName,Stamp> accArcs; 
  output  list<ArcName,Stamp> outArcs; 
algorithm 
  outArcs := 
  matchcontinue (inArcs,accArcs) 
    local
      list<ArcName,Stamp> localAccArcs;
    case ({},localAccArcs) then localAccArcs; 
    case (ARC(DUMMIESTATE(),_,_,_) :: _,localAccArcs) then localAccArcs; 
    case (ARC(GOTOSTATE(_,n),aName,_,_) :: restArcs,localAccArcs) 
      local 
        Integer n; 
        ArcName aName; 
        list<Arc> restArcs;
      equation
        localAccArcs = listAppend(localAccArcs,{(aName,n)}); 
        localAccArcs = simplifyArcs(restArcs,localAccArcs);
      then localAccArcs;    
    case (ARC(STATE(n,_,_,_),aName,_,_) :: restArcs,localAccArcs) 
      local 
        Integer n; 
        ArcName aName; 
        list<Arc> restArcs;
      equation
        localAccArcs = listAppend(localAccArcs,{(aName,n)}); 
        localAccArcs = simplifyArcs(restArcs,localAccArcs);
      then localAccArcs;  
  end matchcontinue;  
end simplifyArcs;

end DFA;