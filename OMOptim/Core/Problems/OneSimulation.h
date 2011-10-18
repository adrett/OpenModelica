// $Id$
/**
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Open Source Modelica Consortium (OSMC),
 * c/o Linkpings universitet, Department of Computer and Information Science,
 * SE-58183 Linkping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR 
 * THIS OSMC PUBLIC LICENSE (OSMC-PL). 
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES RECIPIENT'S ACCEPTANCE
 * OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3, ACCORDING TO RECIPIENTS CHOICE. 
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from OSMC, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or  
 * http://www.openmodelica.org, and in the OpenModelica distribution. 
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 * Main contributor 2010, Hubert Thierot, CEP - ARMINES (France)

 	@file OneSimulation.h
 	@brief Comments for file documentation.
 	@author Hubert Thieriot, hubert.thieriot@mines-paristech.fr
 	Company : CEP - ARMINES (France)
 	http://www-cep.ensmp.fr/english/
 	@version 

  */
#if !defined(_ONESIMULATION_H)
#define _ONESIMULATION_H

#include "Problem.h"
#include "OneSimResult.h"
#include "ProblemConfig.h"
#include "VariablesManip.h"

class Project;
class OneSimulation : public Problem
{

public:
        //OneSimulation(void);
        OneSimulation(Project*,ModClassTree*,ModModelPlus*);
	OneSimulation(const OneSimulation &s);
        Problem* clone() const;
	~OneSimulation(void);

        static QString className(){return "OneSimulation";};
        virtual QString getClassName(){return OneSimulation::className();};



	void setModModelPlus(ModModelPlus*);


	//overwrited functions
	bool checkBeforeComp(QString & error);
        Result* launch(ProblemConfig _config);
	void store(QString destFolder, QString tempDir);
	QDomElement toXmlData(QDomDocument & doc);


        bool canBeStoped();
        void stop();
	


	// get functions
        Variables *overwritedVariables(){return _overwritedVariables;};
	MOVector<ScannedVariable> *scannedVariables(){return _scannedVariables;};
        //OneSimResult* result() const;
	ModModelPlus* modModelPlus();

protected :
	ModModelPlus* _modModelPlus;
        Variables *_overwritedVariables;
        ScannedVariables *_scannedVariables;

};


#endif
