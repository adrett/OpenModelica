/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Linkoping University,
 * Department of Computer and Information Science,
 * SE-58183 Linkoping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3
 * AND THIS OSMC PUBLIC LICENSE (OSMC-PL).
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES RECIPIENT'S
 * ACCEPTANCE OF THE OSMC PUBLIC LICENSE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from Linkoping University, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS
 * OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 * Main Authors 2010: Syed Adeel Asghar, Sonia Tariq
 * Contributors 2011: Abhinn Kothari
 */

#include "ModelicaEditor.h"

//! @class ModelicaEditor
//! @brief An editor for Modelica Text. Subclass QPlainTextEdit

//! Constructor
ModelicaEditor::ModelicaEditor(ProjectTab *pParent)
    : QPlainTextEdit(pParent)
{
    mpParentProjectTab = pParent;
    setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOn);
    setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOn);
    setTabStopWidth(Helper::tabWidth);
    setObjectName(tr("ModelicaEditor"));
    document()->setDocumentMargin(2);
    setLineWrapMode(QPlainTextEdit::NoWrap);
    // depending on the project tab readonly state set the text view readonly state
    setReadOnly(mpParentProjectTab->isReadOnly());
    connect(this, SIGNAL(focusOut()), mpParentProjectTab, SLOT(modelicaEditorTextChanged()));
    connect(this, SIGNAL(textChanged()), SLOT(hasChanged()));

    mpFindWidget = new QWidget;
    mpFindWidget->setContentsMargins(0, 0, 0, 0);
    mpFindWidget->hide();

    mpSearchLabelImage = new QLabel;
    mpSearchLabelImage->setPixmap(QPixmap(":/Resources/icons/search.png"));
    mpSearchLabel = new QLabel(tr("Search"));
    mpSearchTextBox = new QLineEdit;
    connect(mpSearchTextBox, SIGNAL(textChanged(QString)), SLOT(updateButtons()));
    connect(mpSearchTextBox, SIGNAL(returnPressed()), SLOT(findNextText()));

    mpPreviuosButton = new QToolButton;
    mpPreviuosButton->setAutoRaise(true);
    mpPreviuosButton->setText(tr("Previous"));
    mpPreviuosButton->setIcon(QIcon(":/Resources/icons/previous.png"));
    mpPreviuosButton->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
    connect(mpPreviuosButton, SIGNAL(clicked()), SLOT(findPreviuosText()));

    mpNextButton = new QToolButton;
    mpNextButton->setAutoRaise(true);
    mpNextButton->setText(tr("Next"));
    mpNextButton->setIcon(QIcon(":/Resources/icons/next.png"));
    mpNextButton->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
    connect(mpNextButton, SIGNAL(clicked()), SLOT(findNextText()));

    mpMatchCaseCheckBox = new QCheckBox(tr("Match case"));
    mpMatchWholeWordCheckBox = new QCheckBox(tr("Match whole word"));

    mpCloseButton = new QToolButton;
    mpCloseButton->setAutoRaise(true);
    mpCloseButton->setIcon(QIcon(":/Resources/icons/exit.png"));
    connect(mpCloseButton, SIGNAL(clicked()), SLOT(hideFindWidget()));

    mpLineNumberArea = new LineNumberArea(this);
    connect(this, SIGNAL(blockCountChanged(int)), this, SLOT(updateLineNumberAreaWidth(int)));
    connect(this, SIGNAL(updateRequest(QRect,int)), this, SLOT(updateLineNumberArea(QRect,int)));
    connect(this, SIGNAL(cursorPositionChanged()), this, SLOT(highlightCurrentLine()));

    updateLineNumberAreaWidth(0);
    highlightCurrentLine();
    // make previous and next buttons disabled for first time
    updateButtons();
}

//! Uses the OMC parseString API to check the model names inside the Modelica Text
//! @return QStringList a list of model names
QStringList ModelicaEditor::getModelsNames()
{
    OMCProxy *pOMCProxy = mpParentProjectTab->mpParentProjectTabWidget->mpParentMainWindow->mpOMCProxy;
    QStringList models;
    if (toPlainText().isEmpty())
        mErrorString = tr("Start and End modifiers are different");
    else
        models = pOMCProxy->parseString(toPlainText());
    bool existModel = false;
    QStringList existingmodelsList;
    // check if the model already exists
    foreach(QString model, models)
    {
        if (mpParentProjectTab->mModelName.compare(model) != 0)
        {
            if (pOMCProxy->existClass(model))
            {
                existingmodelsList.append(model);
                existModel = true;
            }
        }
    }
    // check if existModel is true
    if (existModel)
    {
        mErrorString = QString(GUIMessages::getMessage(GUIMessages::REDEFING_EXISTING_MODELS)).arg(existingmodelsList.join(",")).append("\n")
                       .append(GUIMessages::getMessage(GUIMessages::DELETE_AND_LOAD));
        return QStringList();
    }
    return models;
}

//! Finds the text in the ModelicaEditor and highlights it. Used by Find Widget.
//! @param text the string to find
//! @param forward true=>finds next item, false=>finds previous item
//! @see findNextText();
//! @see findPreviuosText();
void ModelicaEditor::findText(const QString &text, bool forward)
{
    QTextCursor currentTextCursor = textCursor();
    QTextDocument::FindFlags options;

    if (currentTextCursor.hasSelection())
    {
        currentTextCursor.setPosition(forward ? currentTextCursor.position() : currentTextCursor.anchor(), QTextCursor::MoveAnchor);
    }

    if (!forward)
        options |= QTextDocument::FindBackward;

    if (mpMatchCaseCheckBox->isChecked())
        options |= QTextDocument::FindCaseSensitively;

    if (mpMatchWholeWordCheckBox->isChecked())
        options |= QTextDocument::FindWholeWords;

    bool found = true;
    QTextCursor newTextCursor = document()->find(text, currentTextCursor, options);
    if (newTextCursor.isNull())
    {
        QTextCursor ac(document());
        ac.movePosition(options & QTextDocument::FindBackward ? QTextCursor::End : QTextCursor::Start);
        newTextCursor = document()->find(text, ac, options);
        if (newTextCursor.isNull())
        {
            found = false;
            newTextCursor = currentTextCursor;
        }
    }
    setTextCursor(newTextCursor);

    if (mpSearchTextBox->text().isEmpty())
        found = true;

    if (!found)
    {
        QMessageBox::information(mpParentProjectTab->mpParentProjectTabWidget->mpParentMainWindow, Helper::applicationName + " - Information",
                                 GUIMessages::getMessage(GUIMessages::SEARCH_STRING_NOT_FOUND).arg(text), "OK");
    }
}

//! When user make some changes in the ModelicaEditor text then this method validates the text and show text correct options.
bool ModelicaEditor::validateText()
{
    if (document()->isModified())
    {
        // if the user makes few mistakes in the text then dont let him change the perspective
        if (!emit focusOut())
        {
            MainWindow *pMainWindow = mpParentProjectTab->mpParentProjectTabWidget->mpParentMainWindow;
            QMessageBox *msgBox = new QMessageBox(pMainWindow);
            msgBox->setWindowTitle(QString(Helper::applicationName).append(" - Error"));
            msgBox->setIcon(QMessageBox::Critical);
            msgBox->setText(GUIMessages::getMessage(GUIMessages::ERROR_IN_MODELICA_TEXT)
                            .append(GUIMessages::getMessage(GUIMessages::CHECK_PROBLEMS_TAB))
                            .append(GUIMessages::getMessage(GUIMessages::UNDO_OR_FIX_ERRORS)));
            msgBox->addButton(tr("Undo changes"), QMessageBox::AcceptRole);
            msgBox->addButton(tr("Let me fix errors"), QMessageBox::RejectRole);

            int answer = msgBox->exec();

            switch (answer)
            {
                case QMessageBox::AcceptRole:
                    document()->setModified(false);
                    // revert back to last valid block
                    setPlainText(mLastValidText);
                    return true;
                case QMessageBox::RejectRole:
                    document()->setModified(true);
                    return false;
                default:
                    // should never be reached
                    document()->setModified(true);
                    return false;
            }
        }
        else
        {
            document()->setModified(false);
        }
    }
    return true;
}

//! Reimplementation of resize event.
//! Resets the size of LineNumberArea.
void ModelicaEditor::resizeEvent(QResizeEvent *event)
{
    QPlainTextEdit::resizeEvent(event);

    QRect cr = contentsRect();
    mpLineNumberArea->setGeometry(QRect(cr.left(), cr.top(), lineNumberAreaWidth(), cr.height()));
}

//! Calculate appropriate width for LineNumberArea.
//! @return int width of LineNumberArea.
int ModelicaEditor::lineNumberAreaWidth()
{
    int digits = 1;
    int max = qMax(1, document()->blockCount());
    while (max >= 10)
    {
        max /= 10;
        ++digits;
    }
    int space = 20 + fontMetrics().width(QLatin1Char('9')) * digits;
    return space;
}

//! Updates the width of LineNumberArea.
void ModelicaEditor::updateLineNumberAreaWidth(int newBlockCount)
{
    Q_UNUSED(newBlockCount);
    setViewportMargins(lineNumberAreaWidth(), 0, 0, 0);
}

//! Slot activated when ModelicaEditor cursorPositionChanged signal is raised.
//! Hightlights the current line.
void ModelicaEditor::highlightCurrentLine()
{
    QList<QTextEdit::ExtraSelection> extraSelections;
    QTextEdit::ExtraSelection selection;
    QColor lineColor = QColor(232, 242, 254);
    selection.format.setBackground(lineColor);
    selection.format.setProperty(QTextFormat::FullWidthSelection, true);
    selection.cursor = textCursor();
    selection.cursor.clearSelection();
    extraSelections.append(selection);
    setExtraSelections(extraSelections);
}

//! Slot activated when ModelicaEditor updateRequest signal is raised.
//! Scrolls the LineNumberArea Widget and also updates its width if required.
void ModelicaEditor::updateLineNumberArea(const QRect &rect, int dy)
{
    if (dy)
        mpLineNumberArea->scroll(0, dy);
    else
        mpLineNumberArea->update(0, rect.y(), mpLineNumberArea->width(), rect.height());

    if (rect.contains(viewport()->rect()))
        updateLineNumberAreaWidth(0);
}

//! Activated whenever LineNumberArea Widget paint event is raised.
//! Writes the line numbers for the visible blocks.
void ModelicaEditor::lineNumberAreaPaintEvent(QPaintEvent *event)
{
    QPainter painter(mpLineNumberArea);
    painter.fillRect(event->rect(), QColor(240, 240, 240));

    QTextBlock block = firstVisibleBlock();
    int blockNumber = block.blockNumber();
    int top = (int) blockBoundingGeometry(block).translated(contentOffset()).top();
    int bottom = top + (int) blockBoundingRect(block).height();

    while (block.isValid() && top <= event->rect().bottom())
    {
        if (block.isVisible() && bottom >= event->rect().top())
        {
            QString number = QString::number(blockNumber + 1);
            // make the current highlighted line number darker
            if (blockNumber == textCursor().blockNumber())
            {
                painter.setPen(QColor(64, 64, 64));
            }
            else
            {
                painter.setPen(Qt::gray);
            }
            painter.setFont(document()->defaultFont());
            QFontMetrics fontMetrics (document()->defaultFont());
            painter.drawText(0, top, mpLineNumberArea->width() - 5, fontMetrics.height(), Qt::AlignRight, number);
        }
        block = block.next();
        top = bottom;
        bottom = top + (int) blockBoundingRect(block).height();
        ++blockNumber;
    }
}

//! Reimplementation of QPlainTextEdit::setPlainText method.
//! Makes sure we dont update if the passed text is same.
//! @param text the string to set.
void ModelicaEditor::setPlainText(const QString &text)
{
    if (text != toPlainText())
    {
        QPlainTextEdit::setPlainText(text);
        updateLineNumberAreaWidth(0);
    }
}

//! Slot activated when ModelicaEditor textChanged signal is raised.
//! Checks if model text has changed and then add a * to the model name so that user knows that his current model is not saved.
void ModelicaEditor::hasChanged()
{
    if (mpParentProjectTab->isReadOnly())
        return;

    QString tabName = mpParentProjectTab->mpParentProjectTabWidget->tabText(mpParentProjectTab->mTabPosition);
    if (!tabName.endsWith("*"))
    {
        tabName.append("*");
        mpParentProjectTab->mpParentProjectTabWidget->setTabText(mpParentProjectTab->mTabPosition, tabName);
    }
    mpParentProjectTab->mIsSaved = false;
    if (mpParentProjectTab->isChild())
    {
        // find the parent tree node of this model
        ModelicaTree *pModelicaTree = mpParentProjectTab->mpParentProjectTabWidget->mpParentMainWindow->mpLibrary->mpModelicaTree;
        ModelicaTreeNode *node = pModelicaTree->getNode(mpParentProjectTab->mModelNameStructure);
        while (node->parent() != 0)
            node = dynamic_cast<ModelicaTreeNode*>(node->parent());
        // find the project tab of the parent of this model.
        ProjectTab *pProjectTab;
        MainWindow *pMainWindow = mpParentProjectTab->mpParentProjectTabWidget->mpParentMainWindow;
        pProjectTab = pMainWindow->mpProjectTabs->getProjectTab(node->mNameStructure);
        // if the parent project tab is found then make it unsaved as well.
        if (pProjectTab)
        {
            tabName = mpParentProjectTab->mpParentProjectTabWidget->tabText(pProjectTab->mTabPosition);
            if (!tabName.endsWith("*"))
            {
                tabName.append("*");
                mpParentProjectTab->mpParentProjectTabWidget->setTabText(pProjectTab->mTabPosition, tabName);
            }
            pProjectTab->mIsSaved = false;
        }
    }
}

//! Slot activated when mpCloseButton clicked signal is raised or when user press Esc key.
//! Hides the Find Widget.
void ModelicaEditor::hideFindWidget()
{
    mpFindWidget->hide();
}

//! Slot activated when ModelicaEditor textChanged signal is raised.
//! Makes the Find Widget next and previous buttons enable/disable.
void ModelicaEditor::updateButtons()
{
    const bool enable = !mpSearchTextBox->text().isEmpty();
    mpPreviuosButton->setEnabled(enable);
    mpNextButton->setEnabled(enable);
}

//! Slot activated when mpNextButton clicked signal is raised or when user pressed Enter key.
//! Finds the text in forward direction.
void ModelicaEditor::findNextText()
{
    findText(mpSearchTextBox->text(), true);
}

//! Slot activated when mpPreviousButton clicked signal is raised.
//! Finds the text in backward direction.
void ModelicaEditor::findPreviuosText()
{
    findText(mpSearchTextBox->text(), false);
}

//! @class ModelicaTextHighlighter
//! @brief A syntax highlighter for ModelicaEditor.

//! Constructor
ModelicaTextHighlighter::ModelicaTextHighlighter(ModelicaTextSettings *pSettings, QTextDocument *pParent)
    : QSyntaxHighlighter(pParent)
{
    mpModelicaTextSettings = pSettings;
    initializeSettings();
}

//! Initialized the syntax highlighter with default values.
void ModelicaTextHighlighter::initializeSettings()
{
    QTextDocument *textDocument = qobject_cast<QTextDocument*>(this->parent());
    textDocument->setDefaultFont(QFont(mpModelicaTextSettings->getFontFamily(), mpModelicaTextSettings->getFontSize()));

    mHighlightingRules.clear();
    HighlightingRule rule;
    mTextFormat.setForeground(mpModelicaTextSettings->getTextRuleColor());
    mKeywordFormat.setForeground(mpModelicaTextSettings->getKeywordRuleColor());
    mTypeFormat.setForeground(mpModelicaTextSettings->getTypeRuleColor());
    mSingleLineCommentFormat.setForeground(mpModelicaTextSettings->getCommentRuleColor());
    mMultiLineCommentFormat.setForeground(mpModelicaTextSettings->getCommentRuleColor());
    mFunctionFormat.setForeground(mpModelicaTextSettings->getFunctionRuleColor());
    mQuotationFormat.setForeground(QColor(mpModelicaTextSettings->getQuotesRuleColor()));
    // Priority: keyword > func() > ident > number. Yes, the order matters :)
    mNumberFormat.setForeground(mpModelicaTextSettings->getNumberRuleColor());
    rule.mPattern = QRegExp("[0-9][0-9]*([.][0-9]*)?([eE][+-]?[0-9]*)?");
    rule.mFormat = mNumberFormat;
    mHighlightingRules.append(rule);

    rule.mPattern = QRegExp("\\b[A-Za-z_][A-Za-z0-9_]*");
    rule.mFormat = mTextFormat;
    mHighlightingRules.append(rule);

    QStringList keywordPatterns;
    keywordPatterns << "\\balgorithm\\b"
                    << "\\band\\b"
                    << "\\bannotation\\b"
                    << "\\bassert\\b"
                    << "\\bblock\\b"
                    << "\\bbreak\\b"
                    << "\\bBoolean\\b"
                    << "\\bclass\\b"
                    << "\\bconnect\\b"
                    << "\\bconnector\\b"
                    << "\\bconstant\\b"
                    << "\\bconstrainedby\\b"
                    << "\\bder\\b"
                    << "\\bdiscrete\\b"
                    << "\\beach\\b"
                    << "\\belse\\b"
                    << "\\belseif\\b"
                    << "\\belsewhen\\b"
                    << "\\bencapsulated\\b"
                    << "\\bend\\b"
                    << "\\benumeration\\b"
                    << "\\bequation\\b"
                    << "\\bexpandable\\b"
                    << "\\bextends\\b"
                    << "\\bexternal\\b"
                    << "\\bfalse\\b"
                    << "\\bfinal\\b"
                    << "\\bflow\\b"
                    << "\\bfor\\b"
                    << "\\bfunction\\b"
                    << "\\bif\\b"
                    << "\\bimport\\b"
                    << "\\bin\\b"
                    << "\\binitial\\b"
                    << "\\binner\\b"
                    << "\\binput\\b"
                    << "\\bloop\\b"
                    << "\\bmodel\\b"
                    << "\\bnot\\b"
                    << "\\boperator\\b"
                    << "\\bor\\b"
                    << "\\bouter\\b"
                    << "\\boutput\\b"
                    << "\\bpackage\\b"
                    << "\\bparameter\\b"
                    << "\\bpartial\\b"
                    << "\\bprotected\\b"
                    << "\\bpublic\\b"
                    << "\\bReal\\b"
                    << "\\brecord\\b"
                    << "\\bredeclare\\b"
                    << "\\breplaceable\\b"
                    << "\\breturn\\b"
                    << "\\bstream\\b"
                    << "\\bthen\\b"
                    << "\\btrue\\b"
                    << "\\btype\\b"
                    << "\\bwhen\\b"
                    << "\\bwhile\\b"
                    << "\\bwithin\\b";
    foreach (const QString &pattern, keywordPatterns)
    {
        rule.mPattern = QRegExp(pattern);
        rule.mFormat = mKeywordFormat;
        mHighlightingRules.append(rule);
    }

    QStringList typePatterns;
    typePatterns << "\\bString\\b"
                 << "\\bInteger\\b"
                 << "\\bBoolean\\b"
                 << "\\bReal\\b"
                    ;
    foreach (const QString &pattern, typePatterns)
    {
        rule.mPattern = QRegExp(pattern);
        rule.mFormat = mTypeFormat;
        mHighlightingRules.append(rule);
    }

    rule.mPattern = QRegExp("\\b[A-Za-z0-9_]+(?=\\()");
    rule.mFormat = mFunctionFormat;
    mHighlightingRules.append(rule);

    rule.mPattern = QRegExp("//[^\n]*");
    rule.mFormat = mSingleLineCommentFormat;
    mHighlightingRules.append(rule);

    mCommentStartExpression = QRegExp("/\\*");
    mCommentEndExpression = QRegExp("\\*/");
}

//! Highlights the multilines text.
//! Quoted text or multiline comments.
void ModelicaTextHighlighter::highlightMultiLine(const QString &text)
{
    /* Hand-written recognizer beats the crap known as QRegEx ;) */
    int index = 0, startIndex = 0;
    int blockState = previousBlockState();
    // fprintf(stderr, "%s with blockState %d\n", text.toStdString().c_str(), blockState);

    while (index < text.length())
    {
        switch (blockState) {
            case 1:
                if (text[index] == '*' && index+1<text.length() && text[index+1] == '/') {
                    index++;
                    setFormat(startIndex, index-startIndex+1, mMultiLineCommentFormat);
                    blockState = 0;
                }
                break;
            case 2:
                if (text[index] == '\\') {
                    index++;
                } else if (text[index] == '"') {
                    setFormat(startIndex, index-startIndex+1, mQuotationFormat);
                    blockState = 0;
                }
                break;
            default:
                if (text[index] == '/' && index+1<text.length() && text[index+1] == '*') {
                    startIndex = index++;
                    blockState = 1;
                } else if (text[index] == '"') {
                    startIndex = index;
                    blockState = 2;
                }
        }
        index++;
    }
    switch (blockState) {
        case 1:
            setFormat(startIndex, text.length()-startIndex, mMultiLineCommentFormat);
            setCurrentBlockState(1);
            break;
        case 2:
            setFormat(startIndex, text.length()-startIndex, mQuotationFormat);
            setCurrentBlockState(2);
            break;
    }
}

//! Reimplementation of QSyntaxHighlighter::highlightBlock
void ModelicaTextHighlighter::highlightBlock(const QString &text)
{
    setCurrentBlockState(0);
    setFormat(0, text.length(), mpModelicaTextSettings->getTextRuleColor());
    foreach (const HighlightingRule &rule, mHighlightingRules)
    {
        QRegExp expression(rule.mPattern);
        int index = expression.indexIn(text);
        while (index >= 0)
        {
            int length = expression.matchedLength();
            setFormat(index, length, rule.mFormat);
            index = expression.indexIn(text, index + length);
        }
    }
    highlightMultiLine(text);
}

//! Slot activated whenever ModelicaEditor text changes.
void ModelicaTextHighlighter::settingsChanged()
{
    initializeSettings();
    rehighlight();
}

//! @class GotoLineWidget
//! @brief An interface to goto a specific line in ModelicaEditor.

//! Constructor
GotoLineWidget::GotoLineWidget(ModelicaEditor *pModelicaEditor)
    : QDialog(pModelicaEditor, Qt::WindowTitleHint)
{
    setWindowTitle(QString(Helper::applicationName).append(" - Go to Line"));
    setAttribute(Qt::WA_DeleteOnClose);
    setModal(true);

    mpModelicaEditor = pModelicaEditor;
    mpLineNumberLabel = new QLabel;
    mpLineNumberTextBox = new QLineEdit;
    mpOkButton = new QPushButton(tr("OK"));
    connect(mpOkButton, SIGNAL(clicked()), SLOT(goToLineNumber()));

    QGridLayout *mainLayout = new QGridLayout;
    mainLayout->addWidget(mpLineNumberLabel, 0, 0);
    mainLayout->addWidget(mpLineNumberTextBox, 1, 0);
    mainLayout->addWidget(mpOkButton, 2, 0, 1, 0, Qt::AlignRight);

    setLayout(mainLayout);
}

//! Reimplementation of QDialog::show
void GotoLineWidget::show()
{
    mpLineNumberLabel->setText(QString("Enter line number (1 to ").append(QString::number(mpModelicaEditor->blockCount())).append("):"));
    QIntValidator *intValidator = new QIntValidator(this);
    intValidator->setRange(1, mpModelicaEditor->blockCount());
    mpLineNumberTextBox->setValidator(intValidator);
    setVisible(true);
}

//! Slot activated when mpOkButton clicked signal raised.
void GotoLineWidget::goToLineNumber()
{
    const QTextBlock &block = mpModelicaEditor->document()->findBlockByNumber(mpLineNumberTextBox->text().toInt() - 1); // -1 since text index start from 0
    if (block.isValid())
    {
        QTextCursor cursor(block);
        cursor.movePosition(QTextCursor::Right, QTextCursor::MoveAnchor, 0);
        mpModelicaEditor->setTextCursor(cursor);
        mpModelicaEditor->centerCursor();
    }
    accept();
}
