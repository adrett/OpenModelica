﻿// $Id$
/**
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
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

 	@file OptimResult.h
 	@brief Comments for file documentation.
 	@author Hubert Thieriot, hubert.thieriot@mines-paristech.fr
 	Company : CEP - ARMINES (France)
 	http://www-cep.ensmp.fr/english/
 	@version 0.9 

  */
#if !defined(_OPTIMRESULT_H)
#define _OPTIMRESULT_H

#include "Result.h"
#include "MOOptVector.h"
#include "Variable.h"
#include "OptObjective.h"
#include "OneSimulation.h"
#include "OneSimResult.h"
#include <QtXml/QDomDocument>
#include "EAConfig.h"
#include "Project.h"
#include "Optimization.h"
#include "BlockSubstitutions.h"
#include "CSV.h"
#include "ProblemConfig.h"



class Save;
class Optimization;



class OptimResult : public Result
{
	Q_OBJECT
public:

	OptimResult();
	OptimResult(Project*, ModModelPlus*, Optimization*,ModReader*,ModPlusCtrl*);	
	OptimResult(const OptimResult &_res);
	~OptimResult(void);
	virtual QString getClassName(){return "OptimResult";};

	QDomElement toXMLData(QDomDocument &);
	int problemType(){return Problem::OPTIMIZATION;};

        void updateRecomputedPointsFromFolder();

        void recomputePoints(std::vector<int>,bool forceRecompute = false);

	QString buildOptVarsFrontCSV(QString separator="\t");
	QString buildAllVarsFrontCSV(QString separator="\t");
	QString buildAllVarsFrontCSV(QList<int> vars, QList<int> points,QString separator="\t");
	QString buildAllVarsFrontCSV(QList<int> points,QString separator="\t");

	void exportFrontCSV(QString FileName, bool allVars);

	void setCurScan(int);
	int curScan();

	int nbScans();

	void setCurPoint(int);
	int curPoint();

signals:
	void curPointChanged();
	void curScanChanged(int &);

	
public :
	MOOptVector *optVariablesResults(){return _optVariablesResults;};
	MOOptVector *optObjectivesResults(){return _optObjectivesResults;};
	MOOptVector *recomputedVariables(){return _recomputedVariables;};
	
        QList<int> recomputedPoints(){return _recomputedPoints;};

	// index for each point of subBlocks included (in subBlocks)
	QList<int> _iSubModels;
	// different model configurations (using different BlockSubs)
	QList<BlockSubstitutions*> _subBlocks;

	//save informations
	QString _optVarsFrontFileName;
	QString _allVarsFrontFileName;

protected:
	int _curPoint;
	int _curScan;

	MOOptVector *_optVariablesResults;
	MOOptVector *_optObjectivesResults;
	MOOptVector *_recomputedVariables;

        QList<int> _recomputedPoints;

};





#endif