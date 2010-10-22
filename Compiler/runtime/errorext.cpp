/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2010, Link�pings University,
 * Department of Computer and Information Science,
 * SE-58183 Link�ping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF THIS OSMC PUBLIC
 * LICENSE (OSMC-PL). ANY USE, REPRODUCTION OR DISTRIBUTION OF
 * THIS PROGRAM CONSTITUTES RECIPIENT'S ACCEPTANCE OF THE OSMC
 * PUBLIC LICENSE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from Link�pings University, either from the above address,
 * from the URL: http://www.ida.liu.se/projects/OpenModelica
 * and in the OpenModelica distribution.
 *
 * This program is distributed  WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS
 * OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

#include <iostream>
#include <fstream>
#include <queue>
#include <stack>
#include <list>
#include <string.h>
#include <stdlib.h>
#include <utility>
#include "rtopts.h"

using namespace std;


struct absyn_info{
  std::string fn;
  bool wr;
  int rs;
  int re;
  int cs;
  int ce;
};
// if error_on is true, message is added, otherwise not.
static bool error_on=true;

#include "ErrorMessage.hpp"
static std::string currVariable("");
static absyn_info finfo;
static bool haveInfo(false);
static stack<ErrorMessage*> errorMessageQueue; // Global variable of all error messages.
static vector<pair<int,string> > checkPoints; // a checkpoint has a message index no, and a unique identifier
static string lastDeletedCheckpoint = "";

static void push_message(ErrorMessage *msg)
{
  if (showErrorMessages)
    std::cerr << msg->getFullMessage() << std::endl;
  else
    errorMessageQueue.push(msg);
}

/* Adds a message without file info. */
void add_message(int errorID,
     const char* type,
     const char* severity,
     const char* message,
     std::list<std::string> tokens)
{
  std::string tmp("");
  if(currVariable.length()>0) {
    tmp = "Variable "+currVariable+": " +message;
  }
  else {
    tmp=message;
  }
  if(!haveInfo) {
    ErrorMessage *msg = new ErrorMessage((long)errorID, std::string(type ), std::string(severity), /*std::string(message),*/ tmp, tokens);
    if (errorMessageQueue.empty() || (!errorMessageQueue.empty() && errorMessageQueue.top()->getFullMessage() != msg->getFullMessage())) {
      // std::cerr << "inserting error message "<< msg->getFullMessage() << " on variable "<< currVariable << std::endl; fflush(stderr);
      push_message(msg);
    }
  } else {
    ErrorMessage *msg = new ErrorMessage((long)errorID, std::string(type ), std::string(severity), /*std::string(message),*/ tmp, tokens,
        finfo.rs,finfo.cs,finfo.re,finfo.ce,finfo.wr/*not important?*/,finfo.fn);

    if (errorMessageQueue.empty() || (!errorMessageQueue.empty() && errorMessageQueue.top()->getFullMessage() != msg->getFullMessage())) {
      // std::cerr << "inserting error message "<< msg->getFullMessage() << " on variable "<< currVariable << std::endl;
      // std::cerr << "values: " << finfo.rs << " " << finfo.ce << std::endl; fflush(stderr);
      push_message(msg);
    }
  }
}
/* sets the current_variable(which is beeing instantiated) */
void update_current_component(char* newVar,bool wr, char* fn, int rs, int re, int cs, int ce)
{
  currVariable = std::string(newVar);
  if( (rs+re+cs+ce) > 0) {
    finfo.wr = wr;
    finfo.fn = fn;
    finfo.rs = rs;
    finfo.re = re;
    finfo.cs = cs;
    finfo.ce = ce;
    haveInfo = true;
  } else {
    haveInfo = false;
  }
}
/* Adds a message with file information */
void add_source_message(int errorID,
      const char* type,
      const char* severity,
      const char* message,
      std::list<std::string> tokens,
      int startLine,
      int startCol,
      int endLine,
      int endCol,
      bool isReadOnly,
      const char* filename)
{
  ErrorMessage* msg = new ErrorMessage((long)errorID,
       std::string(type),
       std::string(severity),
       std::string(message),
       tokens,
       (long)startLine,
       (long)startCol,
       (long)endLine,
       (long)endCol,
       isReadOnly,
       std::string(filename));
  if (errorMessageQueue.empty() || (!errorMessageQueue.empty() && errorMessageQueue.top()->getFullMessage() != msg->getFullMessage())) {
    // std::cerr << "inserting error message "<< msg->getFullMessage() << std::endl; fflush(stderr);
    push_message(msg);
  }
}

extern "C"
{

#include <assert.h>

  void printCheckpointStack(void)
  {
    pair<int,string> cp;
    std::string res("");
    printf("Current Stack:\n");
    for (int i=checkPoints.size()-1; i>=0; i--)
    {
      cp = checkPoints[i];
      printf("%5d %s   message:", i, cp.second.c_str());
      while(errorMessageQueue.size() > cp.first && errorMessageQueue.size() > 0){
        res = errorMessageQueue.top()->getMessage()+string(" ")+res;
        delete errorMessageQueue.top();
        errorMessageQueue.pop();
      }
      printf("%s\n", res.c_str());
    }
  }

  void setCheckpoint(const char* id)
  {
    checkPoints.push_back(make_pair(errorMessageQueue.size(),string(id)));
    // fprintf(stderr, "setCheckpoint(%s)\n",id); fflush(stderr);
    //printf(" ERROREXT: setting checkpoint: (%d,%s)\n",(int)errorMessageQueue.size(),id);
  }
  
  void delCheckpoint(const char* id)
  {
    pair<int,string> cp;
    // fprintf(stderr, "delCheckpoint(%s)\n",id); fflush(stderr);
    if(checkPoints.size() > 0){
      //printf(" ERROREXT: deleting checkpoint: %d\n", checkPoints[checkPoints.size()-1]);

      // extract last checkpoint
      cp = checkPoints[checkPoints.size()-1];
      if (0 != strcmp(cp.second.c_str(),id)) {
        printf("ERROREXT: deleting checkpoint called with id:'%s' but top of checkpoint stack has id:'%s'\n",
            id,
            cp.second.c_str());
        printCheckpointStack();
        exit(-1);
      }
      // remember the last deleted checkpoint
      lastDeletedCheckpoint = cp.second;
      checkPoints.pop_back();
    }
    else{
      printf(" ERROREXT: nothing to delete when calling delCheckPoint(%s)\n",id);
      exit(-1);
    }
  }

  void rollBack(const char* id)
  {
    // fprintf(stderr, "rollBack(%s)\n",id); fflush(stderr);
    if(checkPoints.size() > 0){
      //printf(" ERROREXT: rollback to: %d from %d\n",checkPoints.back(),errorMessageQueue.size());
      std::string res("");
      //printf(res.c_str());
      //printf(" rollback from: %d to: %d\n",errorMessageQueue.size(),checkPoints.back().first);
      while(errorMessageQueue.size() > checkPoints.back().first && errorMessageQueue.size() > 0){
        //printf("*** %d deleted %d ***\n",errorMessageQueue.size(),checkPoints.back().first);
        /*if(!errorMessageQueue.empty()){
          res = res+errorMessageQueue.top()->getMessage()+string("\n");
          printf( (string("Deleted: ") + res).c_str());
        }*/
        errorMessageQueue.pop();
      }
      /*if(!errorMessageQueue.empty()){
        res = res+errorMessageQueue.top()->getMessage()+string("\n");
        printf("(%d)new bottom message: %s\n",checkPoints.size(),res.c_str());
      }*/
      pair<int,string> cp;
      cp = checkPoints[checkPoints.size()-1];
      if (0 != strcmp(cp.second.c_str(),id)) {
        printf("ERROREXT: rolling back checkpoint called with id:'%s' but top of checkpoint stack has id:'%s'\n",
            id,
            cp.second.c_str());
        printCheckpointStack();
        exit(-1);
      }
      checkPoints.pop_back();
    } else {
      printf("ERROREXT: caling rollback with id: %s on empty checkpoint stack\n",id);
        exit(-1);
      }
  }

  void* rollBackAndPrint(const char* id)
  {
    std::string res("");
    // fprintf(stderr, "rollBackAndPrint(%s)\n",id); fflush(stderr);
    if(checkPoints.size() > 0){
      while(errorMessageQueue.size() > checkPoints.back().first && errorMessageQueue.size() > 0){
        res = errorMessageQueue.top()->getMessage()+string("\n")+res;
        delete errorMessageQueue.top();
        errorMessageQueue.pop();
      }
      pair<int,string> cp;
      cp = checkPoints[checkPoints.size()-1];
      if (0 != strcmp(cp.second.c_str(),id)) {
        printf("ERROREXT: rolling back checkpoint called with id:'%s' but top of checkpoint stack has id:'%s'\n",
            id,
            cp.second.c_str());
        printCheckpointStack();
        exit(-1);
      }
      checkPoints.pop_back();
    } else {
      printf("ERROREXT: caling rollback with id: %s on empty checkpoint stack\n",id);
        exit(-1);
    }
    // fprintf(stderr, "Returning %s\n", res.c_str());
    return mk_scon((char*)res.c_str());
  }

  /*
   * @author: adrpo
   * checks to see if a checkpoint exists or not AS THE TOP of the stack!
   */
  void* isTopCheckpoint(const char* id)
  {
    pair<int,string> cp;
    //printf("existsCheckpoint(%s)\n",id);
    if(checkPoints.size() > 0){
      //printf(" ERROREXT: searching checkpoint: %d\n", checkPoints[checkPoints.size()-1]);

      // search
      cp = checkPoints[checkPoints.size()-1];
      if (0 == strcmp(cp.second.c_str(),id))
      {
        // found our checkpoint, return true;
        return RML_TRUE;
      }
    }
    // not found
    return RML_FALSE;
  }

  /*
   * @author: adrpo
   * retrieves the last deleted checkpoint
   */
  void* getLastDeletedCheckpoint()
  {
    return mk_scon((char*) lastDeletedCheckpoint.c_str());
  }

  void c_add_message(int errorID,
         const char* type,
         const char* severity,
         const char* message,
         const char** ctokens,
         int nTokens)
  {
    std::list<std::string> tokens;
    for (int i=nTokens-1; i>=0; i--) {
      tokens.push_back(std::string(ctokens[i]));
    }
    add_message(errorID,type,severity,message,tokens);
  }
  void c_add_source_message(int errorID,
         const char* type,
         const char* severity,
         const char* message,
         const char** ctokens,
         int nTokens,
         int startLine,
         int startCol,
         int endLine,
         int endCol,
         int isReadOnly,
         const char* filename)
  {
    std::list<std::string> tokens;
    for (int i=nTokens-1; i>=0; i--) {
      tokens.push_back(std::string(ctokens[i]));
    }
    add_source_message(errorID,type,severity,message,tokens,startLine,startCol,endLine,endCol,isReadOnly,filename);
  }
}
