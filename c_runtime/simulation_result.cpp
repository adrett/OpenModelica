/*
Copyright (c) 1998-2006, Linköpings universitet, Department of
Computer and Information Science, PELAB

All rights reserved.

(The new BSD license, see also
http://www.opensource.org/licenses/bsd-license.php)


Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

* Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in
  the documentation and/or other materials provided with the
  distribution.

* Neither the name of Linköpings universitet nor the names of its
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
*/

/* This file contains functions for storing the result of a simulation to a file.
 * 
 * The solver should call three functions in this file.
 * 1. Call initializeResult before starting simulation, telling maximum number of data points.
 * 2. Call emit() to store data points at given time (taken from globalData structure)
 * 3. Call deinitializeResult with actual number of points produced to store data to file.
 */
 #include <stdio.h>
 #include <errno.h>
 #include <string.h>
 #include "simulation_result.h"
 #include "simulation_runtime.h"
 
 double* simulationResultData=0; 
 long currentPos=0;
 long actualPoints=0; // the number of actual points saved
 int maxPoints;
 
 void add_result(double *data, long *actualPoints);
 
/* \brief
 * 
 * Emits data to result.
 * 
 * \return zero on sucess, non-zero otherwise
 */ 
int emit()
{
  storeExtrapolationData();
  if (actualPoints < maxPoints) {
    add_result(simulationResultData,&actualPoints);
    return 0;
  }
  else {
    cout << "Too many points: " << actualPoints << " max points: " << maxPoints << endl;
    return -1;
  }
}
 
 /* \brief
 * add the values of one step for all variables to the data
 * array to be able to later store this on file.
 */
void add_result(double *data, long *actualPoints)
{
  //save time first
  //cerr << "adding result for time: " << time;
  //cerr.flush();
  data[currentPos++] = globalData->timeValue;
  // .. then states..
  for (int i = 0; i < globalData->nStates; i++, currentPos++) {
    data[currentPos] = globalData->states[i];
  }
  // ..followed by derivatives..
  for (int i = 0; i < globalData->nStates; i++, currentPos++) {
    data[currentPos] = globalData->statesDerivatives[i];
  }
  // .. and last alg. vars.
  for (int i = 0; i < globalData->nAlgebraic; i++, currentPos++) {
    data[currentPos] = globalData->algebraics[i];
  }
  //cerr << "  ... done" << endl;
  (*actualPoints)++;
}

/* \brief initialize result data structures
 * 
 * \param numpoints, maximum number of points that can be stored.
 * \param nx number of states
 * \param ny number of variables
 * \param np number of parameters  (not used in this impl.)
 */

int initializeResult(long numpoints,long nx, long ny, long np)

{
  maxPoints = numpoints;
  
  if (numpoints < 0 ) { // Automatic number of output steps
  	cerr << "Warning automatic output steps not supported in OpenModelica yet." << endl;
  	cerr << "Attempt to solve this by allocating large amount of result data." << endl;
	numpoints = abs(numpoints);
	maxPoints = abs(numpoints);   	
  }
  
  simulationResultData = new double[numpoints*(nx*2+ny+1)];
  if (!simulationResultData) {
    cerr << "Error allocating simulation result data of size " << numpoints *(nx*2+ny)
	      << endl;
    return -1;
  }
  currentPos = 0;
  
  return 0;
}


/* \brief
* stores the result of all variables for all timesteps on a file
* suitable for plotting, etc.
*/

int deinitializeResult(const char * filename)
{
  ofstream f(filename);
  if (!f)
  {
    cerr << "Error, couldn't create output file: [" << filename << "] because" << strerror(errno) << "." << endl;
    return -1;
  }

  // Rather ugly numbers than unneccessary rounding.
  f.precision(numeric_limits<double>::digits10 + 1);
  f << "#Ptolemy Plot file, generated by OpenModelica" << endl;
  f << "#IntervalSize=" << actualPoints << endl;
  f << "TitleText: OpenModelica simulation plot" << endl;
  f << "XLabel: t" << endl << endl;

  int num_vars = 1+globalData->nStates*2+globalData->nAlgebraic;
  
  // time variable.
  f << "DataSet: time"  << endl;
  for(int i = 0; i < actualPoints; ++i)
    f << simulationResultData[i*num_vars] << ", " << simulationResultData[i*num_vars]<< endl;
  f << endl;

  for(int var = 0; var < globalData->nStates; ++var)
  {
    f << "DataSet: " << globalData->statesNames[var] << endl;
    for(int i = 0; i < actualPoints; ++i)
      f << simulationResultData[i*num_vars] << ", " << simulationResultData[i*num_vars + 1+var] << endl;
    f << endl;
  }
  
  for(int var = 0; var < globalData->nStates; ++var)
  {
    f << "DataSet: " << globalData->stateDerivativesNames[var]  << endl;
    for(int i = 0; i < actualPoints; ++i)
      f << simulationResultData[i*num_vars] << ", " << simulationResultData[i*num_vars + 1+globalData->nStates+var] << endl;
    f << endl;
  }
  
  for(int var = 0; var < globalData->nAlgebraic; ++var)
  {
    f << "DataSet: " << globalData->algebraicsNames[var] << endl;
    for(int i = 0; i < actualPoints; ++i)
      f << simulationResultData[i*num_vars] << ", " << simulationResultData[i*num_vars + 1+2*globalData->nStates+var] << endl;
    f << endl;
  }

  f.close();
  if (!f)
  {
    cerr << "Error, couldn't write to output file " << filename << endl;
    return -1;
  }
  return 0;
}
