/*
 * This file is part of ComparePlus plugin for Notepad++
 * Copyright (C)2011 Jean-Sebastien Leroy (jean.sebastien.leroy@gmail.com)
 * Copyright (C)2017-2025 Pavel Nedev (pg.nedev@gmail.com)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Ported to macOS: replaced windows.h, boost::wregex with std::regex,
 * wchar_t/wstring with char/string for UTF-8.
 */

#pragma once

#include <cstdint>
#include <vector>
#include <utility>
#include <memory>
#include <string>
#include <regex>


// Scintilla message forwarding — implemented in the main plugin file
extern intptr_t CallScintilla(int viewNum, unsigned int uMsg, uintptr_t wParam, intptr_t lParam);


// View constants (matching Notepad++ / Scintilla convention)
// These may already be defined as macros by NppPluginInterfaceMac.h
#ifndef MAIN_VIEW
constexpr int MAIN_VIEW = 0;
#endif
#ifndef SUB_VIEW
constexpr int SUB_VIEW  = 1;
#endif


enum class CompareResult
{
	COMPARE_ERROR,
	COMPARE_CANCELLED,
	COMPARE_MATCH,
	COMPARE_MISMATCH
};


enum DiffType
{
	MATCH	= 0,
	IN_1	= 1,
	IN_2	= 2
};


struct section_t
{
	section_t() : off(0), len(0) {}
	section_t(intptr_t o, intptr_t l) : off {o}, len {l} {}

	intptr_t off;
	intptr_t len;
};


struct line_section_t : public section_t
{
	line_section_t() : section_t(), moved {false} {}
	line_section_t(intptr_t o, intptr_t l) : section_t(o, l), moved {false} {}

	bool moved;
};


struct diff_section_t
{
	diff_section_t() : type {DiffType::MATCH} {}
	diff_section_t(DiffType t, intptr_t o1, intptr_t l1, intptr_t o2, intptr_t l2) :
			type {t}, sec1 {o1, l1}, sec2 {o2, l2} {}

	DiffType type;

	section_t sec1;
	section_t sec2;
};


struct CompareOptions
{
	CompareOptions()
	{
		selections[0] = std::make_pair(-1, -1);
		selections[1] = std::make_pair(-1, -1);
	}

	inline void setIgnoreRegex(const std::string& regexStr,
		bool invert, bool inclNomatchLines, bool highlightIgnores, bool iCase)
	{
		if (!regexStr.empty())
		{
			auto regexOptions = std::regex::ECMAScript | std::regex::optimize;

			if (iCase)
				regexOptions |= std::regex::icase;

			ignoreRegex				= std::make_unique<std::regex>(regexStr, regexOptions);
			invertRegex				= invert;
			inclRegexNomatchLines	= inclNomatchLines;
			highlightRegexIgnores	= highlightIgnores;
		}
		else
		{
			ignoreRegex = nullptr;
		}
	}

	inline void clearIgnoreRegex()
	{
		ignoreRegex = nullptr;
	}

	int		newFileViewId;

	bool	findUniqueMode;

	bool	neverMarkIgnored;
	bool	detectMoves;
	bool	detectSubBlockDiffs;
	bool	detectSubLineMoves;
	bool	detectCharDiffs;
	bool	ignoreEmptyLines;
	bool	ignoreFoldedLines;
	bool	ignoreHiddenLines;
	bool	ignoreChangedSpaces;
	bool	ignoreAllSpaces;
	bool	ignoreEOL;
	bool	ignoreCase;

	bool	bookmarksAsSync;

	std::vector<std::pair<intptr_t, intptr_t>> syncPoints;

	bool	recompareOnChange;

	std::unique_ptr<std::regex>		ignoreRegex;
	bool							invertRegex;
	bool							inclRegexNomatchLines;
	bool							highlightRegexIgnores;

	int		changedResemblPercent;

	bool	selectionCompare;

	std::pair<intptr_t, intptr_t>	selections[2];
};


struct AlignmentViewData
{
	intptr_t	line {0};
	int			diffMask {0};
};


struct AlignmentPair
{
	AlignmentViewData main;
	AlignmentViewData sub;
};


using AlignmentInfo_t = std::vector<AlignmentPair>;


struct CompareSummary
{
	inline void clear()
	{
		diffLines	= 0;
		added		= 0;
		removed		= 0;
		moved		= 0;
		changed		= 0;
		match		= 0;

		alignmentInfo.clear();
		diffSections.clear();
	}

	intptr_t	diffLines;
	intptr_t	added;
	intptr_t	removed;
	intptr_t	moved;
	intptr_t	changed;
	intptr_t	match;

	AlignmentInfo_t	alignmentInfo;

	// Below data is needed in case the user wants to generate patch
	int							diff1view;
	std::vector<diff_section_t>	diffSections;
};


// ---------------------------------------------------------------------------
// Color settings — provided by the host plugin.
// On macOS these are simple int (RGB) color values.
// ---------------------------------------------------------------------------
struct CompareColors
{
	int added_part   = 0x00CC00;
	int removed_part = 0xCC0000;
	int moved_part   = 0x0000CC;
	int blank        = 0xCCCCCC;
};

// The host plugin should set these before calling compareViews().
extern CompareColors compareColors;


// ---------------------------------------------------------------------------
// Progress interface — lightweight replacement for the Windows ProgressDlg.
// The host plugin provides an implementation via this interface.
// ---------------------------------------------------------------------------
class ProgressIf
{
public:
	virtual ~ProgressIf() = default;

	virtual void Show() {}
	virtual bool IsCancelled() const { return false; }
	virtual unsigned NextPhase() { return 1; }
	virtual bool SetMaxCount(intptr_t /*max*/, unsigned /*phase*/ = 0) { return true; }
	virtual bool Advance(intptr_t /*cnt*/ = 1, unsigned /*phase*/ = 0) { return true; }
};

using progress_ptr = std::shared_ptr<ProgressIf>;

// The host plugin should set this before calling compareViews().
// If null, a no-op progress is used.
extern progress_ptr globalProgress;


CompareResult compareViews(const CompareOptions& options, const char* progressInfo, CompareSummary& summary);
